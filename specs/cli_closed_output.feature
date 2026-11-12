Feature: CLI closed output
  Scenario: A closed standard output ends quietly
    Given the database server is running
    When I run the kanban wrapper with its standard output closed "prime"
    Then kanban exits with code 141
    And kanban stdout is empty
    And kanban stderr is empty
