Feature: Label colors
  Scenario: A label that the board has not seen gets a color, and a known one keeps it
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api,ui" and priority 2
    And I get the labels of the project
    Then the response status is 200
    And the response contains "\"name\":\"api\""
    And the response contains exactly 2 occurrences of "\"color\":\"#"
    When I add a card titled "Second" with labels "api,docs" and priority 2
    And I get the labels of the project
    Then the response contains exactly 3 occurrences of "\"color\":\"#"
    When I get the project snapshot
    Then the response contains exactly 3 occurrences of "\"color\":\"#"
    When I list project cards
    Then the response does not contain "\"color\""

  Scenario: A label added by an update gets a color
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I send "PATCH" to "/api/cards/1" with the body "{\"labels\":[\"later\"]}"
    And I get the labels of the project
    Then the response contains "\"name\":\"later\""

  Scenario: Change the color of a label
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api" and priority 2
    And I send "PATCH" to "/api/labels/1" with the body "{\"color\":\"#00FF7F\"}"
    Then the response status is 200
    And the response contains "\"color\":\"#00ff7f\""
    When I get the labels of the project
    Then the response contains "#00ff7f"
    When I get board events for "project" after 1
    Then the response contains "label.updated"

  Scenario: A color must be six hex digits after a hash
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api" and priority 2
    And I send "PATCH" to "/api/labels/1" with the body "{\"color\":\"red\"}"
    Then the response status is 400
    And the response contains "INVALID"
    When I send "PATCH" to "/api/labels/1" with the body "{\"color\":\"#12345\"}"
    Then the response status is 400
    When I send "PATCH" to "/api/labels/1" with the body "{}"
    Then the response status is 400
    When I send "PATCH" to "/api/labels/9" with the body "{\"color\":\"#00ff7f\"}"
    Then the response status is 404
    When I get board events for "project" after 1
    Then the response does not contain "label.updated"

  Scenario: Renaming a label renames it on the cards
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api,ui" and priority 2
    And I send "PATCH" to "/api/labels/1" with the body "{\"name\":\"backend\"}"
    Then the response status is 200
    And the response contains "\"name\":\"backend\""
    When I get card 1
    Then the response contains "\"labels\":[\"backend\",\"ui\"]"
    When I get board events for "project" after 1
    Then the response contains "card.updated"
    And the response contains "label.updated"
    When I send "PATCH" to "/api/labels/1" with the body "{\"name\":\"ui\"}"
    Then the response status is 409
    And the response contains "CONFLICT"
    When I search project cards for "backend"
    Then the response contains "First"
