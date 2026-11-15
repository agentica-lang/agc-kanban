Feature: Drift hooks of the plugin
  Background:
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201

  Scenario: A command that has nothing to do with GitHub prints nothing
    When a card "x" is in "Doing" held by "worker" with the link ""
    And I run the post-tool hook as agent "worker" for the command "ls -la" with the output "total 0"
    Then kanban exits with code 0
    And kanban stdout is empty

  Scenario: A new PR is linked to the only card the agent holds in Doing
    When a card "x" is in "Doing" held by "worker" with the link ""
    And a card "x" is in "Doing" held by "other" with the link ""
    And I run the post-tool hook as agent "worker" for the command "gh pr create --title t --body b" with the output "https://github.com/o/r/pull/7"
    Then kanban exits with code 0
    And kanban stdout contains "linked https://github.com/o/r/pull/7 to card 1"
    When I get card 1
    Then the response contains "https://github.com/o/r/pull/7"
    When I get card 2
    Then the response does not contain "pull/7"

  Scenario: An agent with two cards in Doing is told which cards could take the link, and nothing is written
    When a card "x" is in "Doing" held by "worker" with the link ""
    And a card "x" is in "Doing" held by "worker" with the link ""
    And I run the post-tool hook as agent "worker" for the command "gh pr create" with the output "https://github.com/o/r/pull/7"
    Then kanban exits with code 0
    And kanban stdout contains "is not linked on a card. Link it to 1, 2"
    When I get card 1
    Then the response does not contain "pull/7"

  Scenario: A PR that a card already links is not reported
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/7"
    And I run the post-tool hook as agent "worker" for the command "gh pr create" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout is empty

  Scenario: A subagent has no name in the environment, so it writes nothing
    When a card "x" is in "Doing" held by "worker" with the link ""
    And I run the post-tool hook inside a subagent for the command "gh pr create" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "is not linked on a card"
    When I get card 1
    Then the response does not contain "pull/7"

  Scenario: A merged PR names the card that is not done, in the repository of the command
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/x/y/pull/5"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5 --merge -R o/r" with the output "✓ Merged pull request #5 (Fix it)"
    Then kanban stdout contains "card 1 still in Review; mark it done"
    And kanban output does not contain "card 2"

  Scenario: A PR set to merge later is not a merge
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5 --auto -R o/r" with the output "✓ Pull request #5 will be automatically merged"
    Then kanban stdout is empty

  Scenario: A watch_ci run that merged is a merge, one that failed is not
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And I run the post-tool hook as agent "coordinator" for the command "python3 watch_ci.py 5 --repo o/r --merge" with the output "verdict: failed (build)"
    Then kanban stdout is empty
    When I run the post-tool hook as agent "coordinator" for the command "python3 watch_ci.py 5 --repo o/r --merge" with the output "verdict: green (all passed; merged)"
    Then kanban stdout contains "card 1 still in Review"

  Scenario: A closed issue names the cards that link it
    When a card "x" is in "Todo" held by "" with the link "https://github.com/o/r/issues/9"
    And I run the post-tool hook as agent "coordinator" for the command "gh issue close 9 -R o/r" with the output "✓ Closed issue o/r#9 (Title)"
    Then kanban stdout contains "card 1 still in Todo; mark it done"

  Scenario: The coordinator gets the drift of the board, at most every ten minutes
    When a card "x" is in "Review" held by "worker" with the link ""
    And I run the prompt-submit hook as agent "coordinator"
    Then kanban exits with code 0
    And kanban stdout contains "UserPromptSubmit"
    And kanban stdout contains "#1  Review  review-no-pr"
    When I run the prompt-submit hook as agent "coordinator"
    Then kanban stdout is empty

  Scenario: Another agent is not told about the drift
    When a card "x" is in "Review" held by "worker" with the link ""
    And I run the prompt-submit hook as agent "worker"
    Then kanban stdout is empty

  Scenario: A stopped subagent that still holds a card gets a suggestion, which reaches the coordinator once
    When a card "x" is in "Doing" held by "worker" with the link ""
    And the fake claude answers "Here it is: [{\"card\": 1, \"suggest\": \"Review\", \"reason\": \"PR opened\"}]"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker). Take card 1." and ends with "PR opened, CI green"
    Then kanban exits with code 0
    And kanban stdout is empty
    And the fake claude was run with "child=1 args=-p --model haiku"
    And the fake claude was run with "PR opened, CI green"
    And the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - PR opened"
    When I get card 1
    Then the response contains "kanban-hook"
    And the response contains "Review - PR opened"
    And the response contains "\"column\":\"Doing\""
    When I run the post-tool hook as agent "coordinator" for the command "ls" with the output "x"
    Then kanban stdout contains "suggested Review - PR opened"
    And the hook queue is empty
    When I run the post-tool hook as agent "coordinator" for the command "ls" with the output "x"
    Then kanban stdout is empty

  Scenario: A stopped subagent that holds no card costs no model call
    When a card "x" is in "Doing" held by "worker" with the link ""
    And I run the subagent-stop hook for a transcript that starts with "You are ghost (KANBAN_AGENT=ghost)." and ends with "done"
    Then kanban exits with code 0
    And the fake claude was not run
    And the hook queue is empty

  Scenario: An answer that is not the strict JSON is dropped
    When a card "x" is in "Doing" held by "worker" with the link ""
    And the fake claude answers "I think it is done"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    Then kanban exits with code 0
    And kanban stdout is empty
    And the hook queue is empty
