Feature: The web pages

  Scenario: The API key signs in and sets the session cookie
    Given the test server is running
    When I sign in with the key "01234567890123456789012345678901"
    Then the response status is 303
    And the response redirects to "/boards"
    And the response sets the session cookie

  Scenario: The login page has no loading text, because no script draws it
    Given the test server is running
    When I get the page "/login"
    Then the response status is 200
    And the response does not contain "Loading..."

  Scenario: A wrong key does not sign in
    Given the test server is running
    When I sign in with the key "wrong"
    Then the response status is 401
    And the response sets no cookie
    And the response contains "wrong key"

  Scenario Outline: A page needs the session
    Given the test server is running
    When I get the page "<path>"
    Then the response status is 302
    And the response redirects to "/login"

    Examples:
      | path            |
      | /               |
      | /boards         |
      | /boards/project |

  Scenario: The session reads the pages and the key does not replace it
    Given the test server is running
    When I get the page "/boards/project" with the key "01234567890123456789012345678901" as the apikey header
    Then the response status is 302
    When I sign in with the key "01234567890123456789012345678901"
    And I get the page "/boards/project" with the session
    Then the response status is 200
    And the page names the built stylesheet and script
    And the page applies the saved theme before the stylesheet
    And the response contains "Loading..."
    When I get the page "/boards" with the session
    Then the response contains "Loading..."
    When I get the page "/api/auth-check" with the session
    Then the response status is 200

  Scenario: A board opened by its number goes to its slug page
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I sign in with the key "01234567890123456789012345678901"
    And I get the page "/boards/1" with the session
    Then the response status is 302
    And the response redirects to "/boards/project"
    When I get the page "/boards/project" with the session
    Then the response status is 200
    When I get the page "/boards/1?card=5" with the session
    Then the response redirects to "/boards/project?card=5"
    When I get the page "/boards/99" with the session
    Then the response status is 200

  Scenario: A board with a numeric slug is not redirected
    Given the database server is running
    When I post a board named "Numbers" with slug "123" as "agent-1"
    And I sign in with the key "01234567890123456789012345678901"
    And I get the page "/boards/123" with the session
    Then the response status is 200

  Scenario: The built assets are served for a year
    Given the test server is running
    When I get the built stylesheet
    Then the response status is 200
    And the response header "cache-control" contains "immutable"

  Scenario: The session reads the API and never writes it
    Given the test server is running
    When I get the page "/api/boards"
    Then the response status is 401
    When I sign in with the key "01234567890123456789012345678901"
    And I post to "/api/boards" with the session
    Then the response status is 401

  Scenario: Signing out ends the session
    Given the test server is running
    When I sign in with the key "01234567890123456789012345678901"
    And I post to "/logout" with the session
    Then the response status is 303
    And the response redirects to "/login"
    And the response clears the session cookie
