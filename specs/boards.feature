Feature: Boards
  Scenario: Create and list a board
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    And the response contains "Done"
    When I list boards
    Then the response status is 200
    And the response contains "project"

  Scenario: Invalid board input does not create a board
    Given the database server is running
    When I post a board named "" with slug "project" as "agent-1"
    Then the response status is 400
    When I list boards
    Then the response contains "\"boards\":[]"

  Scenario: Missing agent cannot write
    Given the database server is running
    When I post a board named "Project" with slug "project" as ""
    Then the response status is 400

  Scenario: A board snapshot includes cards and its event cursor
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When I get the project snapshot
    Then the response status is 200
    And the response contains "Implement API"
    And the response contains "\"last_event_id\":2"
