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

  Scenario: A move and a done event name the column the card left
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I move card 1 to "Doing"
    And agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And I get board events for "project" with query "after=0&card=1"
    Then the response contains "\"kind\":\"card.moved\""
    And the response contains "\"from\":{\"id\":1,\"name\":\"Todo\"}"
    And the response contains "\"kind\":\"card.done\""
    And the response contains "\"from\":{\"id\":2,\"name\":\"Doing\"}"

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

  Scenario: A backwards page never shows the events of another board
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I post a board named "Other" with slug "other" as "agent-2"
    When I get board events for "other" with query "before=100"
    Then the response status is 200
    And the response contains "agent-2"
    And the response does not contain "agent-1"

  Scenario: A backwards page can be limited to one card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I add a card titled "Second"
    When I get board events for "project" with query "before=100&card=1"
    Then the response status is 200
    And the response contains "\"id\":2,\"kind\""
    And the response does not contain "\"id\":3,\"kind\""
    And the response does not contain "\"id\":1,\"kind\""

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
