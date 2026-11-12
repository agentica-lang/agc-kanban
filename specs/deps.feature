Feature: Card dependencies
  Scenario: An unfinished dependency blocks a claim and cycles are refused
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Blocker"
    Then the response status is 201
    When I add a card titled "Dependent"
    Then the response status is 201
    When I make card 2 depend on card 1
    Then the response status is 201
    And the response contains "\"ready\":false"
    When agent "agent-1" claims card 2
    Then the response status is 409
    And the response contains "BLOCKED"
    When I make card 1 depend on card 2
    Then the response status is 409
    And the response contains "CYCLE"
    When I remove the dependency of card 2 on card 1
    Then the response status is 200
    And the response contains "\"ready\":true"
