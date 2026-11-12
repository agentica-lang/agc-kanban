Feature: The done column keeps the newest card on top
  Scenario: Cards finished one after the other stack newest first
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card add Alpha --board project"
    And I run kanban "card add Beta --board project"
    And I run kanban "card add Gamma --board project"
    Then kanban exits with code 0
    When I run kanban "card done 1 --board project --force"
    And I run kanban "card done 2 --board project --force"
    Then kanban exits with code 0
    When I run kanban "card list --board project --column Done --all"
    Then kanban output lists "Beta" before "Alpha"
    When I get the project snapshot
    Then the response lists "Beta" before "Alpha"
    When I run kanban "card done 3 --board project --force"
    And I get the project snapshot
    Then the response lists "Gamma" before "Beta"
    And the response lists "Beta" before "Alpha"
    And the response contains exactly 1 occurrences of "\"column_id\":4,\"position\":0"
    And the response contains exactly 1 occurrences of "\"column_id\":4,\"position\":1"
    And the response contains exactly 1 occurrences of "\"column_id\":4,\"position\":2"

  Scenario: A card that leaves Done and is finished again goes back on top
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card add Alpha --board project"
    And I run kanban "card add Beta --board project"
    And I run kanban "card done 1 --board project --force"
    And I run kanban "card done 2 --board project --force"
    And I run kanban "card move 2 Doing --board project"
    Then kanban exits with code 0
    When I run kanban "card done 2 --board project --force"
    And I run kanban "card list --board project --column Done --all"
    Then kanban output lists "Beta" before "Alpha"
    When I get the project snapshot
    Then the response contains exactly 1 occurrences of "\"column_id\":4,\"position\":0"
    And the response contains exactly 1 occurrences of "\"column_id\":4,\"position\":1"

  Scenario: A move into Done goes on top unless it names a position
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card add Alpha --board project"
    And I run kanban "card add Beta --board project"
    And I run kanban "card add Gamma --board project"
    And I run kanban "card move 1 Done --board project"
    And I run kanban "card move 2 Done --board project"
    And I run kanban "card list --board project --column Done --all"
    Then kanban output lists "Beta" before "Alpha"
    When I run kanban "card move 3 Done --position 1 --board project"
    Then kanban exits with code 0
    When I run kanban "card list --board project --column Done --all"
    Then kanban output lists "Beta" before "Gamma"
    And kanban output lists "Gamma" before "Alpha"

  Scenario: Other columns still append at the bottom
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card add Alpha --board project"
    And I run kanban "card add Beta --board project"
    And I run kanban "card move 1 Doing --board project"
    And I run kanban "card move 2 Doing --board project"
    And I run kanban "card list --board project --column Doing"
    Then kanban output lists "Alpha" before "Beta"
