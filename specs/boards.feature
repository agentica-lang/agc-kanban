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

  Scenario: A board snapshot says since when each card is in its column, as the card detail does
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I add a card titled "Second"
    And agent "agent-1" claims card 2
    And I move card 2 to "Doing"
    Then the response status is 200
    When agent "agent-1" comments on card 2 with "later"
    Then the snapshot of the project dates card 1 as its card detail does
    And the snapshot of the project dates card 2 as its card detail does
