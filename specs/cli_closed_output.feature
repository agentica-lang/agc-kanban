Feature: CLI closed output
  Scenario: A reader that has left ends the CLI quietly
    When I run the kanban wrapper whose reader has left "prime"
    Then kanban exits with code 141
    And kanban stdout is empty
    And kanban stderr is empty
