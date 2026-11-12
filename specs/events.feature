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

  Scenario: The journal pages backwards from a cursor, newest first
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I add a card titled "Second"
    When I get board events for "project" with query "before=4&limit=2"
    Then the response status is 200
    And the response contains "\"id\":3,\"kind\""
    And the response contains "\"id\":2,\"kind\""
    And the response does not contain "\"id\":1,\"kind\""
    And the response contains "\"last_event_id\":2"
    When I get board events for "project" with query "before=2&limit=2"
    Then the response contains "\"id\":1,\"kind\""
    And the response contains "\"last_event_id\":1"
    When I get board events for "project" with query "before=1"
    Then the response contains "\"events\":[]"

  Scenario Outline: A bad backwards cursor is rejected
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    When I get board events for "project" with query "<query>"
    Then the response status is 400
    And the response contains "INVALID"

    Examples:
      | query              |
      | before=0           |
      | before=2&after=1   |
      | before=x           |
