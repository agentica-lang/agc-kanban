Feature: Card dependencies
  Scenario: An unfinished dependency blocks a claim and cycles are refused
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Blocker"
    Then the response status is 201
    When I add a card titled "Dependent"
    Then the response status is 201
    When I make card 2 depend on card 1
    Then the response status is 201
    And the response contains "\"ready\":false"
    When agent "agent-1" claims card 2
    Then the response status is 409
    And the response contains "BLOCKED"
    When I make card 1 depend on card 2
    Then the response status is 409
    And the response contains "CYCLE"
    When I remove the dependency of card 2 on card 1
    Then the response status is 200
    And the response contains "\"ready\":true"

  Scenario: The holder can add a dependency to a card in progress; the card stays, and closing waits for it
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Blocker"
    And I add a card titled "Work"
    And agent "agent-1" claims card 2
    And agent "agent-1" makes card 2 depend on card 1
    Then the response status is 201
    And the response contains "\"depends_on\":[1]"
    And the response contains "\"claimed_by\":\"agent-1\""
    And the response contains "\"column\":\"Doing\""
    When agent "agent-1" claims card 2
    Then the response status is 200
    And the response contains "\"claimed_by\":\"agent-1\""
    When agent "agent-1" marks card 2 done
    Then the response status is 409
    And the response contains "\"blocked_by\":[1]"
    When I move card 2 to "Done"
    Then the response status is 409
    And the response contains "\"blocked_by\":[1]"
    When I move card 2 to "Review"
    Then the response status is 200
    And the response contains "\"claimed_by\":\"agent-1\""
    When agent "agent-1" releases card 2
    Then the response contains "\"ready\":false"
    When agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And I get card 2
    Then the response contains "\"ready\":true"
    When agent "agent-1" claims card 2
    And agent "agent-1" marks card 2 done
    Then the response status is 200
    And the response contains "\"done\":true"

  Scenario: Another agent needs force to add a dependency to a held card, and force does not skip a cycle
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Blocker"
    And I add a card titled "Work"
    And agent "agent-1" claims card 2
    And agent "agent-2" makes card 2 depend on card 1
    Then the response status is 409
    And the response contains "CLAIMED"
    When agent "agent-2" forcibly makes card 2 depend on card 1
    Then the response status is 201
    And the response contains "\"claimed_by\":\"agent-1\""
    When agent "agent-2" forcibly makes card 1 depend on card 2
    Then the response status is 409
    And the response contains "CYCLE"
    When I get board events for "project" after 0
    Then the response contains exactly 1 occurrences of "\"forced\":true"
    When agent "agent-2" forcibly removes the dependency of card 2 on card 1
    Then the response status is 200
    And the response contains "\"claimed_by\":\"agent-1\""

  Scenario: A card nobody holds is closed only when its dependencies are done
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Blocker"
    And I add a card titled "Work"
    And I make card 2 depend on card 1
    And I move card 2 to "Done"
    Then the response status is 409
    And the response contains "\"blocked_by\":[1]"
    When I move card 2 to "Review"
    Then the response status is 200

  Scenario: A card cannot be created closed with an open dependency
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Blocker"
    And I add a card titled "Late" in column "Done" depending on card 1
    Then the response status is 409
    And the response contains "\"blocked_by\":[1]"
    When agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And I add a card titled "Late" in column "Done" depending on card 1
    Then the response status is 201

  Scenario: Marking a column done is refused while a card in it waits, unless forced
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Blocker"
    And I add a card titled "Work"
    And I make card 2 depend on card 1
    And I move card 2 to "Review"
    And I mark column 3 as done
    Then the response status is 409
    And the response contains "\"blocked_by\":[2]"
    When I get card 2
    Then the response contains "\"done\":false"
    When I forcibly mark column 3 as done
    Then the response status is 200
    When I get card 2
    Then the response contains "\"done\":true"
    When I get board events for "project" after 0
    Then the response contains exactly 1 occurrences of "\"forced\":true"

  Scenario: Cards of a column that wait only for each other can be marked done together
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I add a card titled "Second"
    And I make card 2 depend on card 1
    And I move card 1 to "Review"
    And I move card 2 to "Review"
    And I mark column 3 as done
    Then the response status is 200

  Scenario: Marking a column done leaves the old done column open, so a card that waits for it is refused
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Closed"
    And agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And I add a card titled "Waiting"
    And I make card 2 depend on card 1
    And I move card 2 to "Review"
    And I mark column 3 as done
    Then the response status is 409
    And the response contains "\"blocked_by\":[2]"
    When I get card 2
    Then the response contains "\"done\":false"

  Scenario: A dependency on a done card of another board does not block marking a column done
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I post a board named "Other" with slug "other" as "agent-1"
    And I add a card titled "Closed" to board "other"
    And agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And I add a card titled "Waiting"
    And I make card 2 depend on card 1
    And I move card 2 to "Review"
    And I mark column 3 as done
    Then the response status is 200
    When I get card 2
    Then the response contains "\"done\":true"

