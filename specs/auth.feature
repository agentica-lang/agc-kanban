Feature: API authentication
  Scenario Outline: Data endpoints require the API key
    Given the database server is running
    When I read boards with key "<key>" and agent "agent-1"
    Then the response status is <status>

    Examples:
      | key                              | status |
      |                                  | 401    |
      | wrong                            | 401    |
      | 01234567890123456789012345678901 | 200    |

  Scenario Outline: Writes need a valid agent name
    Given the database server is running
    When I create a board named "Project" with key "01234567890123456789012345678901" and agent "<agent>"
    Then the response status is <status>
    And the response contains "<text>"

    Examples:
      | agent     | status | text           |
      |           | 400    | X-Kanban-Agent |
      | bad agent | 400    | X-Kanban-Agent |
      | agent-1   | 201    | Project        |

  Scenario: An invalid agent names the code and the field
    Given the database server is running
    When I create a board named "Project" with key "01234567890123456789012345678901" and agent "bad agent"
    Then the response status is 400
    And the response contains "\"code\":\"INVALID\""
    And the response contains "\"field\":\"X-Kanban-Agent\""

  Scenario: An agent name longer than 64 characters is rejected
    Given the database server is running
    When I create a board named "Project" with key "01234567890123456789012345678901" and agent "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    Then the response status is 400
    And the response contains "INVALID"

  Scenario: A wrong key is reported before the agent is validated
    Given the database server is running
    When I create a board named "Project" with key "wrong" and agent "bad agent"
    Then the response status is 401
    And the response contains "UNAUTHORIZED"

  Scenario: Reads do not need an agent header
    Given the database server is running
    When I create a board named "Project" with key "01234567890123456789012345678901" and agent "agent-1"
    Then the response status is 201
    When I read boards with key "01234567890123456789012345678901" and agent ""
    Then the response status is 200
    And the response contains "Project"
