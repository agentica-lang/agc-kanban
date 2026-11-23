Feature: Milestones
  Scenario: A new milestone has no cards, and the label of the cards is its link to them
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"0.37.0\",\"description\":\"The big one\",\"due_on\":\"2099-12-01\"}"
    Then the response status is 201
    And the response contains "\"name\":\"0.37.0\""
    And the response contains "\"description\":\"The big one\""
    And the response contains "\"due_on\":\"2099-12-01\""
    And the response contains "\"open\":0,\"closed\":0,\"percent\":0"
    When I get the milestones of the project
    Then the response contains "\"state\":\"open\""
    When I get the labels of the project
    Then the response contains "\"name\":\"0.37.0\""
    When I get board events for "project" after 0
    Then the response contains "milestone.updated"

  Scenario: Done cards are closed, even when the auto archive hides them, and a dropped card counts in neither
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A" with labels "0.37.0" and priority 2
    And I add a card titled "B" with labels "0.37.0" and priority 2
    And I add a card titled "C" with labels "0.37.0" and priority 2
    And I add a card titled "D" with labels "0.37.0,other" and priority 2
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"0.37.0\"}"
    Then the response contains "\"open\":4,\"closed\":0,\"percent\":0"
    When I move card 1 to "Done"
    And I get the milestones of the project
    Then the response contains "\"open\":3,\"closed\":1,\"percent\":25"
    When I move card 2 to "Done"
    And I get the milestones of the project
    Then the response contains "\"open\":2,\"closed\":2,\"percent\":50"
    When agent "agent-1" archives card 1
    And I get the milestones of the project
    Then the response contains "\"open\":2,\"closed\":2,\"percent\":50"
    When I move card 3 to "Doing"
    And agent "agent-1" archives card 3
    And I get the milestones of the project
    Then the response contains "\"open\":1,\"closed\":2,\"percent\":66"

  Scenario: Closing a milestone hides it from the default list, and reopening brings it back
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"first\",\"due_on\":\"2099-01-01\"}"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"second\"}"
    And I send "PATCH" to "/api/milestones/1" with the body "{\"state\":\"closed\"}"
    Then the response status is 200
    And the response contains "\"state\":\"closed\""
    When I get the milestones of the project
    Then the response contains "second"
    And the response does not contain "first"
    When I get the milestones of the project with state "closed"
    Then the response contains "first"
    And the response does not contain "second"
    When I get the milestones of the project with state "all"
    Then the response lists "second" before "first"
    When I send "PATCH" to "/api/milestones/1" with the body "{\"state\":\"open\"}"
    And I get the milestones of the project
    Then the response lists "first" before "second"
    And the response contains "\"closed_at\":null"

  Scenario: Open milestones come by due date and an overdue one with open cards says so
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A" with labels "late" and priority 2
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"undated\"}"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"soon\",\"due_on\":\"2098-01-01\"}"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"late\",\"due_on\":\"2020-01-01\"}"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"empty\",\"due_on\":\"2019-01-01\"}"
    And I get the milestones of the project
    Then the response lists "empty" before "late"
    And the response lists "late" before "soon"
    And the response lists "soon" before "undated"
    And the response contains exactly 1 occurrences of "\"overdue\":true"
    When I send "PATCH" to "/api/milestones/1" with the body "{\"due_on\":\"\"}"
    Then the response contains "\"due_on\":null"
    And the response contains "\"overdue\":false"

  Scenario: Removing a milestone keeps the label on the cards, and renaming the label keeps the milestone
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A" with labels "0.37.0" and priority 2
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"0.37.0\"}"
    And I send "PATCH" to "/api/labels/1" with the body "{\"name\":\"0.38.0\"}"
    And I get the milestones of the project
    Then the response contains "\"name\":\"0.38.0\""
    And the response contains "\"open\":1"
    When I send "DELETE" to "/api/milestones/1" with the body ""
    Then the response status is 204
    When I get the milestones of the project
    Then the response does not contain "0.38.0"
    When I get card 1
    Then the response contains "\"labels\":[\"0.38.0\"]"
    When I get board events for "project" after 0
    Then the response contains "milestone.removed"

  Scenario: A bad request is refused
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\" \"}"
    Then the response status is 400
    When I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"x\",\"due_on\":\"2026-02-30\"}"
    Then the response status is 400
    When I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"x\",\"due_on\":\"soon\"}"
    Then the response status is 400
    When I send "POST" to "/api/boards/nowhere/milestones" with the body "{\"name\":\"x\"}"
    Then the response status is 404
    When I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"x\"}"
    Then the response status is 201
    When I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"x\"}"
    Then the response status is 409
    When I send "PATCH" to "/api/milestones/1" with the body "{}"
    Then the response status is 400
    When I send "PATCH" to "/api/milestones/1" with the body "{\"state\":\"half\"}"
    Then the response status is 400
    When I send "PATCH" to "/api/milestones/1" with the body "{\"due_on\":\"2026-13-01\"}"
    Then the response status is 400
    When I send "PATCH" to "/api/milestones/9" with the body "{\"state\":\"closed\"}"
    Then the response status is 404
    When I send "DELETE" to "/api/milestones/9" with the body ""
    Then the response status is 404
    When I send "GET" to "/api/boards/project/milestones?state=half" with the body ""
    Then the response status is 400

  Scenario: The same name on two boards is two milestones
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I post a board named "Other" with slug "other" as "agent-1"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"0.37.0\"}"
    And I send "POST" to "/api/boards/other/milestones" with the body "{\"name\":\"0.37.0\"}"
    Then the response status is 201
    When I send "POST" to "/api/boards/other/cards" with the body "{\"title\":\"A\",\"labels\":[\"0.37.0\"]}"
    And I get the milestones of the project
    Then the response contains "\"open\":0"
    When I send "GET" to "/api/boards/other/milestones" with the body ""
    Then the response contains "\"open\":1"

  Scenario: The web session reads milestones and cannot write them
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I send "POST" to "/api/boards/project/milestones" with the body "{\"name\":\"0.37.0\"}"
    And I sign in
    And I get the page "/api/boards/project/milestones" with the session
    Then the response status is 200
    And the response contains "0.37.0"
    When I post "/api/boards/project/milestones" with the session as agent "agent-1" and the body "{\"name\":\"web\"}"
    Then the response status is 401
    When I patch "/api/milestones/1" with the session as agent "agent-1" and the body "{\"state\":\"closed\"}"
    Then the response status is 401
