Feature: Card comments
  Scenario: A comment is recorded with its author and event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-2" comments on card 1 with "Please add tests"
    Then the response status is 201
    And the response contains "Please add tests"
    And the response contains "\"author\":\"agent-2\""
    When I get card 1
    Then the response contains "Please add tests"
    When I get board events for "project" after 2
    Then the response contains "comment.added"

  Scenario: Another agent may comment on a claimed card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-1" claims card 1
    Then the response status is 200
    When agent "agent-2" comments on card 1 with "Found while working on #1"
    Then the response status is 201
    When agent "agent-2" retitles card 1 to "Hijacked"
    Then the response status is 409

  Scenario: Commenting on a missing card is not found
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When agent "agent-1" comments on card 999 with "Ghost"
    Then the response status is 404
    And the response contains "NOT_FOUND"

  Scenario: An empty comment changes nothing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-1" comments on card 1 with " "
    Then the response status is 400
    And the response contains "INVALID"
    When I get board events for "project" after 2
    Then the response contains "\"events\":[]"
