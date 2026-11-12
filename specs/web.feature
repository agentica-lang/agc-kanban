Feature: The web pages

  Scenario: The API key signs in and sets the session cookie
    Given the test server is running
    When I sign in with the key "01234567890123456789012345678901"
    Then the response status is 303
    And the response redirects to "/boards"
    And the response sets the session cookie

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
    When I get the page "/api/auth-check" with the session
    Then the response status is 200

  Scenario: The built assets are served for a year
    Given the test server is running
    When I get the built stylesheet
    Then the response status is 200
    And the response header "cache-control" contains "immutable"
