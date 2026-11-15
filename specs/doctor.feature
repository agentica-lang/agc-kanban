Feature: kanban doctor
  Background:
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201

  Scenario: A board that matches GitHub is clean
    When a card "x" is in "Doing" held by "worker" with the link "https://github.com/o/r/issues/1"
    And I run kanban doctor "" while gh says "{\"o/r#1\":\"open\"}"
    Then kanban exits with code 0
    And kanban stdout contains "no drift on project (1 open cards)"

  Scenario: Each kind of drift is one line with the card, the column, the reason and the action, in one gh call
    When a card "x" is in "Todo" held by "" with the link "https://github.com/o/r/issues/1"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/2"
    And a card "x" is in "Review" held by "worker" with the link ""
    And a card "x" is in "Doing" held by "worker" with the link ""
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/5"
    And agent "worker" links card 5 to "https://github.com/o/r/pull/6"
    And I run kanban doctor "--stale-minutes 0" while gh says "{\"o/r#1\":\"closed\",\"o/r#2\":\"merged\",\"o/r#5\":\"merged\",\"o/r#6\":\"open-pull\"}"
    Then kanban exits with code 5
    And kanban stdout contains "#1  Todo  issue-closed  its issue is closed (https://github.com/o/r/issues/1); next: kanban card done 1"
    And kanban stdout contains "#2  Review  pr-merged"
    And kanban stdout contains "#3  Review  review-no-pr  in Review with no PR link; next: kanban card update 3 --link PR_URL"
    And kanban stdout contains "#4  Doing  doing-stale"
    And kanban output does not contain "#5  "
    And the gh log has 1 calls

  Scenario: A Doing card with a recent event is not stale by default
    When a card "x" is in "Doing" held by "worker" with the link ""
    And I run kanban doctor "" while gh says "{}"
    Then kanban exits with code 0

  Scenario: The report is JSON with --json
    When a card "x" is in "Review" held by "worker" with the link ""
    And I run kanban doctor "--json" while gh says "{}"
    Then kanban exits with code 5
    And kanban stdout is a JSON document
    And kanban stdout contains "\"kind\":\"review-no-pr\""

  Scenario: A gh that fails exits 6 and still prints what the board alone shows
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/2"
    And a card "x" is in "Review" held by "worker" with the link ""
    And I run kanban doctor "" while gh says "fail"
    Then kanban exits with code 6
    And kanban stdout contains "#2  Review  review-no-pr"
    And kanban stderr contains "GitHub checks skipped"

  Scenario: No server is exit 3
    When I run kanban against a dead server "doctor --board project"
    Then kanban exits with code 3

  Scenario: --no-github makes no gh call
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/2"
    And I run kanban doctor "--no-github" while gh says "{\"o/r#2\":\"merged\"}"
    Then kanban exits with code 0
    And the gh log has 0 calls

  Scenario: Merged work of a card whose issue is still open is reported only in Review or Doing
    When a card "x" is in "Todo" held by "" with the link "https://github.com/o/r/issues/1"
    And agent "agent-1" links card 1 to "https://github.com/o/r/pull/2"
    And a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/issues/1"
    And agent "worker" links card 2 to "https://github.com/o/r/pull/2"
    And I run kanban doctor "" while gh says "{\"o/r#1\":\"open\",\"o/r#2\":\"merged\"}"
    Then kanban exits with code 5
    And kanban output does not contain "#1  "
    And kanban stdout contains "#2  Review  pr-merged  its linked PRs are all merged"
    And kanban stdout contains "kanban card move 2 Todo for the next slice"

  Scenario: A PR closed without a merge is not drift
    When a card "x" is in "Review" held by "worker" with the link "https://github.com/o/r/pull/2"
    And I run kanban doctor "" while gh says "{\"o/r#2\":\"closed-pull\"}"
    Then kanban exits with code 0
