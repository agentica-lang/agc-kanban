Feature: CLI card list as TSV
  Scenario: A line has seven tab-separated fields, with no header
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First" with labels "api,two words" and priority 1
    And I add a card titled "Second"
    And I add a card titled "Third" with labels "ui" and priority 0
    And I make card 2 depend on card 1
    And agent "worker" claims card 1
    And I run kanban "card list --board project --format tsv"
    Then kanban exits with code 0
    And kanban tsv has 3 lines
    And kanban tsv line 1 is "2|Todo||0|2||Second"
    And kanban tsv line 2 is "3|Todo||1|0|ui|Third"
    And kanban tsv line 3 is "1|Doing|worker|0|1|api,two words|First"
    When I run kanban "card list --board project --format text"
    Then kanban stdout contains "#1  Doing  worker  First [api, two words]"

  Scenario: Every filter selects the same cards as in text
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First" with labels "api" and priority 2
    And I add a card titled "Second" with labels "ui" and priority 2
    And I add a card titled "Third" with labels "api" and priority 2
    And I make card 3 depend on card 1
    And agent "agent-1" claims card 2
    And I run kanban "card add Review-card --board project --column Review"
    And I run kanban "card list --board project --format tsv --ready"
    Then kanban tsv has 2 lines
    And kanban tsv line 1 is "1|Todo||1|2|api|First"
    And kanban tsv line 2 is "4|Review||1|2||Review-card"
    When I run kanban "card list --board project --format tsv --mine"
    Then kanban tsv has 1 lines
    And kanban tsv line 1 is "2|Doing|agent-1|0|2|ui|Second"
    When I run kanban "card list --board project --format tsv --claimed-by agent-1"
    Then kanban tsv has 1 lines
    When I run kanban "card list --board project --format tsv --column Review"
    Then kanban tsv has 1 lines
    And kanban tsv line 1 is "4|Review||1|2||Review-card"
    When I run kanban "card list --board project --format tsv --label api"
    Then kanban tsv has 2 lines
    And kanban tsv line 2 is "3|Todo||0|2|api|Third"

  Scenario: A done card needs --all and an archived card is never listed
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Finished"
    And I add a card titled "Hidden"
    And I add a card titled "Open"
    And agent "agent-1" claims card 1
    And agent "agent-1" marks card 1 done
    And agent "agent-1" archives card 2
    And I run kanban "card list --board project --format tsv"
    Then kanban tsv has 1 lines
    And kanban tsv line 1 is "3|Todo||1|2||Open"
    When I run kanban "card list --board project --format tsv --all"
    Then kanban tsv has 2 lines
    And kanban stdout contains "Finished"
    And kanban output does not contain "Hidden"

  Scenario: A tab or a line break in a title becomes a space and the title stays last
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card whose title has a tab and a line break
    And I run kanban "card list --board project --format tsv"
    Then kanban tsv has 1 lines
    And kanban tsv line 1 is "1|Todo||1|2||one two three"

  Scenario: An empty board prints nothing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "card list --board project --format tsv"
    Then kanban exits with code 0
    And kanban stdout is empty

  Scenario: A format other than text or tsv is a usage error
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "card list --board project --format csv"
    Then kanban exits with code 2
    And kanban stdout is empty
    And kanban output contains "is not one of text, tsv"

  Scenario: tsv with --json is a usage error and no card is printed
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I run kanban "card list --board project --format tsv --json"
    Then kanban exits with code 2
    And kanban stdout contains "USAGE"
    And kanban output does not contain "First"
    When I run kanban "card list --board project --format text --json"
    Then kanban exits with code 0
    And kanban stdout contains "\"cards\""
