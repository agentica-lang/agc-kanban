Feature: The web pages

  Scenario: The login page has no loading text, because no script draws it
    Given the test server is running
    When I get the page "/login"
    Then the response status is 200
    And the response does not contain "Loading..."

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
      | /boards/project/milestones |

  Scenario: The session reads the pages and the key does not replace it
    Given the database server is running
    When I get the page "/boards/project" with the key "01234567890123456789012345678901" as the apikey header
    Then the response status is 302
    When I sign in
    And I get the page "/boards/project" with the session
    Then the response status is 200
    And the page names the built stylesheet and script
    And the page applies the saved theme before the stylesheet
    And the response contains "Loading..."
    When I get the page "/api/auth-check" with the session
    Then the response status is 200

  Scenario: A board opened by its number goes to its slug page
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I sign in
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
    And I sign in
    And I get the page "/boards/123" with the session
    Then the response status is 200

  Scenario: The built assets are served for a year
    Given the test server is running
    When I get the built stylesheet
    Then the response status is 200
    And the response header "cache-control" contains "immutable"

  Scenario: The session reads the API and never writes it
    Given the database server is running
    When I get the page "/api/boards"
    Then the response status is 401
    When I sign in
    And I post to "/api/boards" with the session
    Then the response status is 401

  Scenario: The home page without boards says what to run
    Given the database server is running
    When I sign in
    And I get the page "/boards" with the session
    Then the response status is 200
    And the response contains "A shared Kanban board for coding agents"
    And the response contains "No boards yet"
    And the response contains "kanban board create"
    And the response does not contain "Loading..."

  Scenario: The home page shows each board with its cards, blocked cards and agents
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A"
    And I add a card titled "B"
    And I add a card titled "C"
    And I add a card titled "D"
    And I move card 4 to "Done"
    And agent "bob" claims card 1
    And I make card 3 depend on card 2
    And I sign in
    And I get the page "/boards" with the session
    Then the response status is 200
    And the response contains "href=\"/boards/project\""
    And the response contains "<b>2</b> <span>Todo</span>"
    And the response contains "<b>1</b> <span>Doing</span>"
    And the response contains "<b>0</b> <span>Review</span>"
    And the response contains "<b>1</b> <span>Done</span>"
    And the response contains "1 blocked"
    And the response contains "<span class=\"claimer light\" style=\"--hue:157\">bob</span>"
    And the response contains "1 agent working"
    And the response contains "just now"
    And the response contains "1 board"

  Scenario: The milestones page shows the percent, the link to the cards and the due date, and the tabs split open from closed
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A" with labels "0.37.0" and priority 2
    And I add a card titled "B" with labels "0.37.0" and priority 2
    And I add a card titled "C" with labels "0.37.0" and priority 2
    And I add a card titled "D" with labels "0.37.0" and priority 2
    And I add a card titled "E" with labels "0.37.0" and priority 2
    And I move card 1 to "Done"
    And I move card 2 to "Done"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"0.37.0\",\"description\":\"The big one\",\"due_on\":\"2020-12-01\"}"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"retired\"}"
    And I send "PATCH" to "/api/milestones/2" with the body "{\"state\":\"closed\"}"
    And I sign in
    And I get the page "/boards/project/milestones" with the session
    Then the response status is 200
    And the response contains "Milestones"
    And the response contains "40% complete · 3 open · 2 closed"
    And the response contains "href=\"/boards/project?label=0.37.0\""
    And the response contains "The big one"
    And the response contains "Due by 2020-12-01"
    And the response contains "due overdue"
    And the response contains "Open (1)"
    And the response contains "Closed (1)"
    And the response does not contain "retired"
    And the response does not contain "Loading..."
    When I get the page "/boards/project/milestones?state=closed" with the session
    Then the response contains "retired"
    And the response contains "closed</span>"
    And the response does not contain "0.37.0\""
    When I get the page "/boards" with the session
    Then the response contains "href=\"/boards/project/milestones\""

  Scenario: The milestones page escapes a name, and says what to run when there is none
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I sign in
    And I get the page "/boards/project/milestones" with the session
    Then the response contains "No milestones yet"
    And the response contains "kanban milestone create"
    When I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"<b>x\",\"description\":\"<i>y\"}"
    And I get the page "/boards/project/milestones" with the session
    Then the response contains "&lt;b&gt;x"
    And the response contains "&lt;i&gt;y"
    And the response contains "label=%3Cb%3Ex"
    And the response does not contain "<b>x"
    And the response does not contain "<i>y"
    When I get the page "/boards/nowhere/milestones" with the session
    Then the response status is 404

  Scenario: A claim whose lease ran out shows no agent
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A"
    And I add a card titled "B"
    And agent "bob" claims card 1
    And agent "carol" claims card 2
    And the lease of card 2 has run out
    And I sign in
    And I get the page "/boards" with the session
    Then the response contains "--hue:157\">bob</span>"
    And the response does not contain "carol"
    And the response contains "1 agent working"

  Scenario: An agent with a dark hue gets the plain chip, and one with a light hue the light chip
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A"
    And I add a card titled "B"
    And agent "web" claims card 1
    And agent "bob" claims card 2
    And I sign in
    And I get the page "/boards" with the session
    Then the response contains "<span class=\"claimer\" style=\"--hue:228\">web</span>"
    And the response contains "<span class=\"claimer light\" style=\"--hue:157\">bob</span>"

  Scenario: A claimed card in the done column shows no agent
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A"
    And I move card 1 to "Done"
    And the store keeps card 1 claimed by "bob"
    And I sign in
    And I get the page "/boards" with the session
    Then the response does not contain "bob"
    And the response contains "0 agents working"

  Scenario: A board with no cards and a board with every card done
    Given the database server is running
    When I post a board named "Empty" with slug "empty" as "agent-1"
    And I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A"
    And I move card 1 to "Done"
    And I sign in
    And I get the page "/boards" with the session
    Then the response contains "No cards yet"
    And the response contains "All done"
    And the response does not contain "blocked"

  Scenario: The home page escapes a board name and has no write controls
    Given the database server is running
    When I post a board named "<b>x</b>" with slug "project" as "agent-1"
    And I add the column "<i>y</i>" at position 1
    And I sign in
    And I get the page "/boards" with the session
    Then the response contains "&lt;b&gt;x&lt;/b&gt;"
    And the response does not contain "<b>x</b>"
    And the response contains "&lt;i&gt;y&lt;/i&gt;"
    And the response does not contain "<i>y</i>"
    And the response contains exactly 1 occurrences of "<form"
    And the response does not contain "<input"
    And the response does not contain "<textarea"

  Scenario: The session edits a label color and nothing else
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api" and priority 2
    And I sign in
    And I patch "/api/labels/1" with the session as agent "web" and the body "{\"color\":\"#00ff7f\"}"
    Then the response status is 200
    And the response contains "#00ff7f"
    When I patch "/api/labels/1" with the session as agent "" and the body "{\"color\":\"#00ff7f\"}"
    Then the response status is 400
    When I patch "/api/labels/1" with the session as agent "web" and the body "{\"name\":\"renamed\"}"
    Then the response status is 401
    When I patch "/api/labels/1x" with the session as agent "web" and the body "{\"color\":\"#00ff7f\"}"
    Then the response status is 401
    When I patch "/api/cards/1" with the session as agent "web" and the body "{\"title\":\"x\"}"
    Then the response status is 401
    When I get board events for "project" after 1
    Then the response contains "label.updated"
