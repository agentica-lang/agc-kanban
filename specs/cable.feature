Feature: Live board updates

  Scenario: A claim from the CLI reaches a signed-in browser
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I sign in
    And a live client with the session subscribes to the board "project"
    Then the live client receives a frame containing "confirm_subscription"
    When I run kanban "card claim 1 --board project"
    Then kanban exits with code 0
    And the live client receives a frame containing "card.claimed"

  Scenario: A browser with no session is turned away
    Given the database server is running
    When a live client without a session subscribes to the board "project"
    Then the live client receives a frame containing "unauthorized"

  Scenario: A browser whose session was signed out is turned away
    Given the database server is running
    When I sign in
    And I post to "/logout" with the session
    And a live client with the session subscribes to the board "project"
    Then the live client receives a frame containing "unauthorized"

  Scenario: Signing out closes the live view of the session
    Given the database server is running
    When I sign in
    And a live client with the session subscribes to the board "project"
    Then the live client receives a frame containing "confirm_subscription"
    When I post to "/logout" with the session
    Then the live client receives a frame containing "remote"
