Feature: Card search
  Scenario: A title match ranks above a body match, and a prefix finds the word
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Update docs" with the body "the login page needs a note"
    Then the response status is 201
    When I add a card titled "Fix login redirect"
    Then the response status is 201
    When I add a card titled "Unrelated"
    Then the response status is 201
    When I search project cards for "login"
    Then the response status is 200
    And the response lists "Fix login redirect" before "Update docs"
    And the response does not contain "Unrelated"
    When I search project cards for "logi"
    Then the response contains "Fix login redirect"
    And the response contains "Update docs"

  Scenario: FTS syntax in the input never errors
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Fix login AND logout"
    Then the response status is 201
    When I search project cards for "\"login"
    Then the response status is 200
    When I search project cards for "login*"
    Then the response status is 200
    And the response contains "Fix login"
    When I search project cards for "-login"
    Then the response status is 200
    When I search project cards for "AND"
    Then the response status is 200
    When I search project cards for "login AND OR NOT ( ) : ^ NEAR(a b)"
    Then the response status is 200
    When I search project cards for "- * \""
    Then the response status is 200
    And the response contains "\"results\":[]"

  Scenario: Done cards come only with all, and an edited card is found by its new text and its comments
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Finished login work"
    Then the response status is 201
    When agent "agent-1" claims card 1
    Then the response status is 200
    When agent "agent-1" marks card 1 done
    Then the response status is 200
    When I search project cards for "login"
    Then the response status is 200
    And the response does not contain "Finished login work"
    When I search project cards for "login" with all
    Then the response contains "Finished login work"
    When I add a card titled "Old name"
    Then the response status is 201
    When I search project cards for "renamed"
    Then the response does not contain "Old name"
    When agent "agent-2" retitles card 2 to "Renamed thing"
    Then the response status is 200
    When I search project cards for "renamed"
    Then the response contains "Renamed thing"
    When I search project cards for "Old"
    Then the response does not contain "Renamed thing"
    When agent "agent-2" comments on card 2 with "needs a zebra"
    Then the response status is 201
    When I search project cards for "zebra"
    Then the response contains "Renamed thing"
