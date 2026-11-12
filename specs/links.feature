Feature: Card links
  Scenario: A card carries its links from the start, without repeats, and each change is an event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Linked" with the link "https://github.com/o/r/pull/7"
    Then the response status is 201
    And the response contains "\"links\":[\"https://github.com/o/r/pull/7\"]"
    When agent "agent-1" links card 1 to "https://github.com/o/r/pull/7"
    Then the response status is 200
    And the response contains "\"links\":[\"https://github.com/o/r/pull/7\"]"
    And the response contains "\"version\":1"
    When agent "agent-1" links card 1 to "https://ci.example.com/run/5"
    Then the response contains "\"links\":[\"https://github.com/o/r/pull/7\",\"https://ci.example.com/run/5\"]"
    And the response contains "\"version\":2"
    When agent "agent-1" unlinks card 1 from "https://not.there/x"
    Then the response status is 200
    And the response contains "\"links\":[\"https://github.com/o/r/pull/7\",\"https://ci.example.com/run/5\"]"
    And the response contains "\"version\":2"
    When agent "agent-1" unlinks card 1 from "https://github.com/o/r/pull/7"
    Then the response contains "\"links\":[\"https://ci.example.com/run/5\"]"
    When I get board events for "project" after 1
    Then the response contains exactly 2 occurrences of "card.updated"
    And the response contains "\"links\":[\"https://ci.example.com/run/5\"]"

  Scenario Outline: Only plain http(s) links are kept
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Linked"
    And agent "agent-1" links card 1 to "<url>"
    Then the response status is 400
    And the response contains "\"field\":\"links\""
    When I get card 1
    Then the response contains "\"links\":[]"

    Examples:
      | url                                    |
      | javascript:alert(1)                    |
      | data:text/html,hi                      |
      | https://x.io/a\\"onmouseover=\\"x      |
      | https://x.io/<script>alert(1)</script> |
      | https:///no-host                       |
      | ftp://x.io/file                        |
      | https://x.io/a b                       |
      | https://user:pass@x.io/                |
      | https://x.io/a b                       |
      | https://x.io/‮gnp.exe                  |
      | https://x.io/ab                      |
      | https://bücher.example/                |

  Scenario: A card holds at most 50 links, and an unlink list at most 50
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Linked"
    And agent "agent-1" links card 1 to 50 URLs
    Then the response status is 200
    When agent "agent-1" links card 1 to "https://github.com/o/r/issues/7"
    Then the response status is 400
    And the response contains "\"field\":\"links\""
    When agent "agent-1" unlinks 51 URLs from card 1
    Then the response status is 400
    And the response contains "\"field\":\"links\""

  Scenario: Links stay on a done card and after a move
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Linked"
    And agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And agent "agent-2" links card 1 to "https://github.com/o/r/pull/7"
    Then the response status is 200
    When I move card 1 to "Todo"
    Then the response contains "\"links\":[\"https://github.com/o/r/pull/7\"]"

  Scenario: The CLI adds, removes and shows links
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "card add Linked --board project --link https://github.com/o/r/pull/7 --link https://github.com/o/r/issues/3"
    Then kanban exits with code 0
    When I run kanban "card update 1 --link https://github.com/o/r/pull/7 --unlink https://github.com/o/r/issues/3 --link=https://ci.example.com/run/5"
    Then kanban exits with code 0
    When I run kanban "card show 1"
    Then kanban output contains "link: https://github.com/o/r/pull/7"
    And kanban output contains "link: https://ci.example.com/run/5"
    And kanban output does not contain "issues/3"
    When I run kanban "card show 1 --json"
    Then kanban output contains "\"links\":[\"https://github.com/o/r/pull/7\",\"https://ci.example.com/run/5\"]"
    When I run kanban "card update 1 --link javascript:alert(1)"
    Then kanban exits with code 1
    And kanban output contains "INVALID"

  Scenario: The CLI reads --link only before -- and never as the value of another option
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "card add --board project -- --link"
    Then kanban exits with code 0
    And kanban output contains "--link"
    When I run kanban "card update 1 --body --link https://github.com/o/r/pull/7"
    Then kanban exits with code 2
    And kanban output contains "--body needs a value"
    When I run kanban "card show 1 --json"
    Then kanban output contains "\"title\":\"--link\""
    And kanban output contains "\"links\":[]"

  Scenario: A server older than links does not drop them silently
    Given a server older than links is running
    When I run kanban "card update 1 --link https://github.com/o/r/pull/7"
    Then kanban exits with code 3
    And kanban stderr contains "UNSUPPORTED"
    When I run kanban "card update 1 --title Renamed"
    Then kanban exits with code 0
