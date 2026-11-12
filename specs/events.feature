Feature: Board events
  Scenario: A board creation event can be read and paginated
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I get board events for "project" after 0
    Then the response status is 200
    And the response contains "board.created"
    And the response contains "agent-1"
    When I get board events for "project" after 1
    Then the response status is 200
    And the response contains "\"events\":[]"

  Scenario: An unknown board has no event stream
    Given the database server is running
    When I get board events for "missing" after 0
    Then the response status is 404
    And the response contains "NOT_FOUND"

  Scenario: A negative event cursor is rejected
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I get board events for "project" after -1
    Then the response status is 400
    And the response contains "INVALID"
