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

  Scenario: A new PR is linked to the card of the agent whose repository and branch it matches
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 1 to "feat-x"
    And a card "x" is in "Doing" held by "other" with the link "https://github.com/o/r/issues/4"
    And agent "other" sets the branch of card 2 to "feat-y"
    And I run the post-tool hook as agent "worker" for the command "gh pr create --head feat-x --title t" with the output "https://github.com/o/r/pull/7"
    Then kanban exits with code 0
    And kanban stdout contains "linked https://github.com/o/r/pull/7 to card 1"
    When I get card 1
    Then the response contains "https://github.com/o/r/pull/7"
    When I get card 2
    Then the response does not contain "pull/7"

  Scenario: A side PR of another branch is not linked to the card the agent holds
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 1 to "feat-x"
    And I run the post-tool hook as agent "worker" for the command "gh pr create --head docs-fix" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "is not linked on a card. Link it to 1"
    When I get card 1
    Then the response does not contain "pull/7"

  Scenario: A PR of another repository is not linked, and no card that is only about other repositories is offered
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 1 to "feat-x"
    And I run the post-tool hook as agent "worker" for the command "gh pr create --head feat-x" with the output "https://github.com/x/y/pull/7"
    Then kanban exits with code 0
    And kanban stdout is empty
    When I get card 1
    Then the response does not contain "pull/7"

  Scenario: The hint offers the cards of the PR's repository and the cards with no link
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And a card "x" is in "Doing" held by "worker" with the link "https://github.com/x/y/issues/4"
    And a card "x" is in "Doing" held by "worker" with the link ""
    And I run the post-tool hook as agent "worker" for the command "gh pr create" with the output "https://github.com/x/y/pull/7"
    Then kanban stdout contains "Link it to 2, 3, if it is"

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

  Scenario: A subagent has no name of its own, so only the repository and branch of a card link a PR
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 1 to "feat-x"
    And I run the post-tool hook inside a subagent for the command "gh pr create" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "is not linked on a card"
    When I get card 1
    Then the response does not contain "pull/7"
    When I run the post-tool hook inside a subagent for the command "gh pr create --head feat-x" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "linked https://github.com/o/r/pull/7 to card 1"
    When I get card 1
    Then the response contains "https://github.com/o/r/pull/7"

  Scenario: A merged PR names the card that is not done, in the repository of the command
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/x/y/pull/5"
    And gh says "{\"o/r#5\":\"merged\",\"x/y#5\":\"open-pull\"}"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5 --merge -R o/r" with the output "✓ Merged pull request #5 (Fix it)"
    Then kanban stdout contains "card 1 still in Review; next: kanban card done 1"
    And kanban output does not contain "card 2"

  Scenario: A merge by URL names the card of that repository
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/x/y/pull/5"
    And gh says "{\"o/r#5\":\"open-pull\",\"x/y#5\":\"merged\"}"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge https://github.com/x/y/pull/5 --squash" with the output "✓ Squashed and merged pull request #5 (Fix it)"
    Then kanban stdout contains "card 2 still in Review"
    And kanban output does not contain "card 1"

  Scenario: A merge with no argument takes the repository and number from what gh printed
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/x/y/pull/5"
    And gh says "{\"o/r#5\":\"merged\",\"x/y#5\":\"open-pull\"}"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge --squash" with the output "✓ Squashed and merged pull request o/r#5 (Fix it)"
    Then kanban stdout contains "card 1 still in Review"
    And kanban output does not contain "card 2"

  Scenario: A PR set to merge later is not a merge
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5 --auto -R o/r" with the output "✓ Pull request #5 will be automatically merged"
    Then kanban stdout is empty

  Scenario: A watch_ci run that merged is a merge, one that failed is not
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And gh says "{\"o/r#5\":\"merged\"}"
    And I run the post-tool hook as agent "coordinator" for the command "python3 watch_ci.py 5 --repo o/r --merge" with the output "verdict: failed (build)"
    Then kanban stdout is empty
    When I run the post-tool hook as agent "coordinator" for the command "python3 watch_ci.py 5 --repo o/r --merge" with the output "verdict: green (all passed; merged)"
    Then kanban stdout contains "card 1 still in Review"

  Scenario: A closed issue names the cards that link it
    When a card "x" is in "Todo" held by "" with the link "https://github.com/o/r/issues/9"
    And gh says "{\"o/r#9\":\"closed\"}"
    And I run the post-tool hook as agent "coordinator" for the command "gh issue close 9 -R o/r" with the output "✓ Closed issue o/r#9 (Title)"
    Then kanban stdout contains "card 1 still in Todo; next: kanban card done 1"

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
    And the fake claude was run with "Review: an open PR is green"
    And the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - Haiku: PR opened"
    When I get card 1
    Then the response contains "kanban-hook"
    And the response contains "Hook suggestion (Haiku: PR opened; the coordinator decides): Review."
    And the response contains "\"column\":\"Doing\""
    When I run the post-tool hook as agent "coordinator" for the command "ls" with the output "x"
    Then kanban stdout contains "suggested Review - Haiku: PR opened"
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

  Scenario: Queued suggestions reach the coordinator even when the doctor hangs, and the doctor is killed with its children
    When a card "x" is in "Review" held by "worker" with the link ""
    And the hook queue has "queued suggestion"
    And I run the prompt-submit hook as agent "coordinator" with a doctor that hangs
    Then kanban exits with code 0
    And kanban stdout contains "queued suggestion"
    And the hung doctor and its child are gone

  Scenario: A reviewer whose brief names a line is not that line
    When a card "x" is in "Doing" held by "simd" with the link ""
    And the fake claude answers "[{\"card\": 1, \"suggest\": \"Todo\", \"reason\": \"gave up\"}]"
    And I run the subagent-stop hook for a transcript that starts with "Review the PR that line simd opened for card 1." and ends with "CHANGES: 3 findings"
    Then kanban exits with code 0
    And the fake claude was not run
    And the hook queue is empty
    When I get card 1
    Then the response does not contain "kanban-hook"

  Scenario: The subagent is known by the name in its own commands, and its handed-back report is what Haiku reads
    When a card "x" is in "Doing" held by "worker" with the link ""
    And the fake claude answers "[7, {\"card\": \"1\", \"suggest\": \"Review\", \"reason\": \"PR open\"}]"
    And I run the subagent-stop hook for a transcript that starts with "Do the card.", runs "kanban card claim 1 --agent worker" and hands back "REPORT: PR 9 opened, CI green"
    Then kanban exits with code 0
    And the fake claude was run with "REPORT: PR 9 opened, CI green"
    And the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - Haiku: PR open"

  Scenario: A merged PR of a parent card whose issue is still open says nothing in Todo and a slice hint in Doing
    When a card "x" is in "Todo" held by "" with the link "https://github.com/o/r/issues/9"
    And agent "agent-1" links card 1 to "https://github.com/o/r/pull/5"
    And a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/9"
    And agent "worker" links card 2 to "https://github.com/o/r/pull/5"
    And gh says "{\"o/r#9\":\"open\",\"o/r#5\":\"merged\"}"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5 -R o/r" with the output "✓ Merged pull request #5 (Slice)"
    Then kanban stdout contains "card 2 still in Doing; next: kanban card move 2 Todo for the next slice, or kanban card done 2 if the issue is finished"
    And kanban output does not contain "card 1"

  Scenario: A merge notice is silent when gh cannot be read
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And gh says "fail"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5 -R o/r" with the output "✓ Merged pull request #5 (Slice)"
    Then kanban exits with code 0
    And kanban stdout is empty

  Scenario: A flag inside the quoted body of a PR is not a flag
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 1 to "feat-x"
    And I run the post-tool hook as agent "worker" for the command "gh pr create --body 'built with -H feat-x' --title t" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "is not linked on a card"
    When I get card 1
    Then the response does not contain "pull/7"
    When I run the post-tool hook as agent "worker" for the command "gh pr create --body 'built with -H other' --head=feat-x && echo done" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "linked https://github.com/o/r/pull/7 to card 1"

  Scenario: A command that only quotes gh pr create is not one
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And I run the post-tool hook as agent "worker" for the command "echo 'run gh pr create later'" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout is empty

  Scenario: A card id that is a boolean in the answer of Haiku is dropped
    When a card "x" is in "Doing" held by "worker" with the link ""
    And the fake claude answers "[{\"card\": true, \"suggest\": \"Todo\", \"reason\": \"x\"}]"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    Then kanban exits with code 0
    And the hook queue is empty

  Scenario: A line break ends a command, and inside quotes it stays in the argument
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/x/y/pull/5"
    And gh says "{\"x/y#5\":\"merged\"}"
    And I run the post-tool hook as agent "coordinator" for the command "gh pr merge 5\\ngh pr view 5 -R x/y" with the output "✓ Merged pull request #5 (Fix it)"
    Then kanban exits with code 0
    And kanban stdout is empty
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 2 to "feat-x"
    And I run the post-tool hook as agent "worker" for the command "gh pr create --body 'built\\nwith -H other' --head feat-x" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "linked https://github.com/o/r/pull/7 to card 2"

  Scenario: gh counts only as the command word, by name or by path
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" sets the branch of card 1 to "feat-x"
    And I run the post-tool hook as agent "worker" for the command "echo gh pr create --head feat-x" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout is empty
    When I run the post-tool hook as agent "worker" for the command "GH_TOKEN=t /usr/bin/gh pr create --head feat-x" with the output "https://github.com/o/r/pull/7"
    Then kanban stdout contains "linked https://github.com/o/r/pull/7 to card 1"

  Scenario Outline: A subagent that waits on its own background work is not finished, so it gets no suggestion
    When a card "x" is in "Doing" held by "worker" with the link ""
    And the fake claude answers "[{\"card\": 1, \"suggest\": \"Todo\", \"reason\": \"x\"}]"
    And I run the subagent-stop hook for worker after "<transcript>"
    Then kanban exits with code 0
    And the hook <verdict>

    Examples:
      | transcript                                 | verdict          |
      | bash b1                                    | skipped the stop |
      | monitor m1                                 | skipped the stop |
      | agent a9                                   | skipped the stop |
      | bash b1, notice b1                         | suggested a move |
      | bash b1, attached notice b1                | suggested a move |
      | bash b1, stop b1                           | suggested a move |
      | bash b1, handback                          | suggested a move |
      | bash b1, handback, attached notice b2      | suggested a move |
      | bash b1, monitor m1, notice b1             | skipped the stop |
      | handback, coordinator message, bash b1     | skipped the stop |
      | fetch                                      | suggested a move |

  Scenario: The newest PR open and green is Review by rule, logged, and scored against the move the card got
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" links card 1 to "https://github.com/o/r/pull/5"
    And agent "worker" links card 1 to "https://github.com/o/r/pull/7"
    And gh says "{\"o/r#3\":\"open\",\"o/r#5\":\"merged\",\"o/r#7\":\"open-pull:pass\"}"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "PR 7 green"
    Then kanban exits with code 0
    And the gh log has 1 calls
    And the fake claude was not run
    And the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - rule: newest PR green"
    And the hook log contains "\"card\": 1, \"column\": \"Doing\", \"agent\": \"worker\", \"suggest\": \"Review\", \"source\": \"rule: newest PR green\""
    And the hook log contains "{\"item\": \"o/r#7\", \"kind\": \"pr\", \"state\": \"open\", \"ci\": \"pass\", \"newest\": true}"
    When agent "worker" moves card 1 to "Review"
    And I score the logged hook suggestions
    Then kanban exits with code 0
    And kanban stdout contains "rule: 1/1 hits (100%)"

  Scenario: An open PR whose CI is pending keeps the card, and one whose CI fails keeps it with a note
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/5"
    And a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/7"
    And gh says "{\"o/r#5\":\"open-pull:pending\",\"o/r#7\":\"open-pull:fail\"}"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "pushed"
    Then kanban exits with code 0
    And the fake claude was not run
    And the hook queue contains "card 2 (worker stopped, now in Doing): suggested keep - rule: CI failing on o/r#7"
    And the hook queue does not contain "card 1"
    And the hook log contains "\"suggest\": \"keep\", \"source\": \"rule: CI pending\""

  Scenario: Every linked PR merged and the issue closed suggest Done by rule
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/issues/3"
    And agent "worker" links card 1 to "https://github.com/o/r/pull/5"
    And gh says "{\"o/r#3\":\"closed\",\"o/r#5\":\"merged\"}"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    Then the fake claude was not run
    And the hook queue contains "card 1 (worker stopped, now in Review): suggested Done - rule: PRs merged or closed, issue closed"

  Scenario: Merged PRs of an open issue go to Haiku as facts, never with a title or body from GitHub
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/agentica-lang/agentica/issues/985"
    And agent "worker" links card 1 to "https://github.com/agentica-lang/agentica/pull/1840"
    And agent "worker" links card 1 to "https://github.com/agentica-lang/agentica/pull/1841"
    And gh says "{\"agentica-lang/agentica#985\":\"open\",\"agentica-lang/agentica#1840\":\"merged\",\"agentica-lang/agentica#1841\":\"merged\"}"
    And the fake claude answers "[{\"card\": 1, \"suggest\": \"Todo\", \"reason\": \"next slice\"}]"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "PRs 1840 and 1841 are open"
    Then the fake claude was run with "pr agentica-lang/agentica#1840 merged"
    And the fake claude was run with "pr agentica-lang/agentica#1841 merged newest"
    And the fake claude was run with "issue agentica-lang/agentica#985 open"
    And the fake claude was not run with "IGNORE THE RULES"
    And the gh log does not contain "title"
    And the gh log does not contain "body"
    And the hook queue contains "card 1 (worker stopped, now in Doing): suggested Todo - Haiku: next slice"

  Scenario: The CI rules look at the newest PR by its creation time, and an issue closed alone is Done
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/9"
    And agent "worker" links card 1 to "https://github.com/o/r/pull/5/files#diff"
    And a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/4"
    And gh says "{\"o/r#9\":\"open-pull:fail@2026-01-01T00:00:00Z\",\"o/r#5\":\"open-pull:pass@2026-02-01T00:00:00Z\",\"o/r#4\":\"closed\"}"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    Then the fake claude was not run
    And the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - rule: newest PR green"
    And the hook queue contains "card 2 (worker stopped, now in Doing): suggested Done - rule: issue closed"

  Scenario: The same suggestion is told again once the card moved between the stops
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/1"
    And gh says "{\"o/r#1\":\"open-pull:pass\"}"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "green"
    And agent "worker" moves card 1 to "Review"
    And agent "worker" moves card 1 to "Doing"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "green again"
    Then the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - rule: newest PR green" twice

  Scenario Outline: A card whose GitHub links are not all read goes to Haiku, not to a rule
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/30"
    And agent "worker" links card 1 to <links>
    And gh says "{\"*\":\"merged\",\"o/r#30\":\"closed\",\"o/r#21\":\"open-pull:pass\"}"
    And the fake claude answers "[{\"card\": 1, \"suggest\": \"Todo\", \"reason\": \"unsure\"}]"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    Then the hook queue contains "suggested Todo - Haiku: unsure"
    And the hook queue does not contain "rule:"

    Examples:
      | links                                    |
      | 21 URLs                                  |
      | "https://github.com/o/r/actions/runs/1"  |

  Scenario: Repeated stops tell a suggestion once, and score counts hits, misses, keeps and a suggestion of the own column
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/1"
    And a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/2"
    And a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/pull/3"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/4"
    And gh says "{\"o/r#1\":\"open-pull:pass\",\"o/r#2\":\"open\",\"o/r#3\":\"open-pull:pending\",\"o/r#4\":\"open-pull:pass\"}"
    And the fake claude answers "[{\"card\": 2, \"suggest\": \"Todo\", \"reason\": \"left\"}]"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    And I run the subagent-stop hook for a transcript that starts with "You are worker (KANBAN_AGENT=worker)." and ends with "done"
    Then the hook queue contains "card 1 (worker stopped, now in Doing): suggested Review - rule: newest PR green" once
    And the hook queue contains "card 2 (worker stopped, now in Doing): suggested Todo - Haiku: left" once
    And the hook queue does not contain "card 3"
    And the hook queue does not contain "card 4"
    When agent "worker" moves card 1 to "Review"
    And agent "worker" moves card 2 to "Review"
    And I score the logged hook suggestions
    Then kanban exits with code 0
    And kanban stdout contains "rule: 3/3 hits (100%)"
    And kanban stdout contains "haiku: 0/1 hits (0%)"
    And kanban stdout contains "all: 3/4 hits (75%)"
