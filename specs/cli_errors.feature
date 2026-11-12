Feature: CLI failures
  Scenario: A missing key is refused
    Given the database server is running
    When I run kanban without a key "board list"
    Then kanban exits with code 3
    And kanban output contains "UNAUTHORIZED"

  Scenario: A write without an agent is a usage error
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban without an agent "card add First --board project"
    Then kanban exits with code 2
    And kanban output contains "INVALID"

  Scenario: An unknown board is not found
    Given the database server is running
    When I run kanban "board show nope"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"

  Scenario: A card claimed by another agent is a lost race
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When agent "agent-2" claims card 1
    Then the response status is 200
    When I run kanban "card claim 1 --board project"
    Then kanban exits with code 4
    And kanban output contains "CLAIMED"

  Scenario: Two agents claiming one card end with one 0 and one 4
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When two agents run kanban "card claim 1 --board project"
    Then kanban exit codes are "0,4"
    And kanban output contains "CLAIMED"

  Scenario: Errors go to stderr and leave stdout clean
    Given the database server is running
    When I run kanban "card show 999"
    Then kanban exits with code 1
    And kanban stdout is empty
    And kanban stderr contains "NOT_FOUND"

  Scenario: A JSON error is a document on stdout
    Given the database server is running
    When I run kanban "card show 999 --json"
    Then kanban exits with code 1
    And kanban stdout contains "\"error\""
    And kanban stdout contains "\"code\":\"NOT_FOUND\""

  Scenario: A dead server is a 3
    Given the database server is running
    When I run kanban against a dead server "board list"
    Then kanban exits with code 3
    And kanban output contains "UNAVAILABLE"

  Scenario: A busy server is retried and then refused
    Given a server is busy "1"
    When I run kanban "whoami"
    Then kanban exits with code 3
    And kanban output contains "BUSY"

  Scenario: A busy server that recovers needs no retry by hand
    Given a server is busy "0"
    When I run kanban "whoami"
    Then kanban exits with code 0
    And kanban output contains "health: ok"

  Scenario: Nothing ready is a normal refusal
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card next --board project"
    Then kanban exits with code 1
    And kanban output contains "NO_READY_CARD"

  Scenario: A non-holder is refused unless forced
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When agent "agent-2" claims card 1
    Then the response status is 200
    When I run kanban "card done 1 --board project"
    Then kanban exits with code 1
    And kanban output contains "NOT_CLAIMER"
    When I run kanban "card done 1 --board project --force"
    Then kanban exits with code 0

  Scenario: Creating the configured board uses its slug
    Given the database server is running
    When I run kanban with board "slugx" "board create Named"
    Then kanban exits with code 0
    And kanban output contains "slugx"

  Scenario: Help prints the usage on stdout
    Given the database server is running
    When I run kanban "card add --help"
    Then kanban exits with code 0
    And kanban stdout contains "kanban card add"
