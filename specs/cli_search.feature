Feature: CLI search
  Scenario: Search by title and body, best first, done cards only with --all
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Update docs" with the body "the login page needs a note"
    Then the response status is 201
    When I add a card titled "Fix login redirect"
    Then the response status is 201
    When I add a card titled "Done login work"
    Then the response status is 201
    When agent "agent-1" claims card 3
    Then the response status is 200
    When agent "agent-1" marks card 3 done
    Then the response status is 200
    When I run kanban "card search login --board project"
    Then kanban exits with code 0
    And kanban output lists "Fix login redirect" before "Update docs"
    And kanban output does not contain "Done login work"
    When I run kanban "card search logi --board project --all"
    Then kanban exits with code 0
    And kanban output contains "Done login work"
    When I run kanban "card search login --board project --json --limit 1"
    Then kanban exits with code 0
    And kanban output contains "\"results\""
    And kanban output contains "Fix login redirect"
    And kanban output does not contain "Update docs"

  Scenario: Odd input does not fail
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card search AND --board project"
    Then kanban exits with code 0
    When I run kanban "card search login* --board project"
    Then kanban exits with code 0
