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
