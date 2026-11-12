Feature: Cards
  Scenario: Create and read a card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    And the response contains "Implement API"
    And the response contains "\"ready\":true"
    When I get card 1
    Then the response status is 200
    And the response contains "Implement API"
    And the response contains "\"comments\":[]"

  Scenario: Missing card returns not found
    Given the database server is running
    When I get card 999
    Then the response status is 404
    And the response contains "NOT_FOUND"

  Scenario: List cards on a board
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When I list project cards
    Then the response status is 200
    And the response contains "Implement API"

  Scenario: Update a free card and record the event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-2" retitles card 1 to "Implement HTTP API"
    Then the response status is 200
    And the response contains "Implement HTTP API"
    When I get card 1
    Then the response contains "Implement HTTP API"
    When I get board events for "project" after 1
    Then the response contains "card.updated"

  Scenario: Only the holder may change a claimed card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-1" claims card 1
    Then the response status is 200
    When agent "agent-2" retitles card 1 to "Hijacked"
    Then the response status is 409
    And the response contains "CLAIMED"
    When agent "agent-1" retitles card 1 to "Owned"
    Then the response status is 200
    When agent "agent-2" forces a new title on card 1 to "Orchestrated"
    Then the response status is 200
    And the response contains "Orchestrated"

  Scenario: Invalid card updates change nothing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-1" retitles card 1 to ""
    Then the response status is 400
    And the response contains "INVALID"
    When I get card 1
    Then the response contains "Implement API"
    When I get board events for "project" after 2
    Then the response contains "\"events\":[]"

  Scenario: Filters run in SQL and reject a bad boolean
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I add a card titled "Second"
    Then the response status is 201
    When I make card 2 depend on card 1
    Then the response status is 201
    When I list project cards with query "ready=1"
    Then the response status is 200
    And the response contains "First"
    And the response does not contain "Second"
    When I list project cards with query "ready=yes"
    Then the response status is 400
    And the response contains "INVALID"
    When I list project cards with query "done=1"
    Then the response status is 200
    And the response does not contain "First"

  Scenario: Claim next with nothing ready is not found
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Only"
    Then the response status is 201
    When agent "agent-1" claims card 1
    Then the response status is 200
    When agent "agent-1" marks card 1 done
    Then the response status is 200
    When agent "agent-2" claims the next card
    Then the response status is 404
    And the response contains "NO_READY_CARD"

  Scenario: A card shows the time in each column it went through
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Implement API"
    And I get card 1
    Then the response contains "\"stays\":[{\"column_id\":1,\"name\":\"Todo\""
    And the response contains "\"column\":\"Todo\",\"since\":"
    When I move card 1 to "Doing"
    And I move card 1 to "Todo"
    And agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And I get card 1
    Then the response contains exactly 1 occurrences of "\"name\":\"Todo\""
    And the response contains exactly 1 occurrences of "\"name\":\"Doing\""
    And the response does not contain "\"name\":\"Done\""
    And the response contains "\"done\":true,\"total_ms\":"
