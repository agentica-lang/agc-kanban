Feature: Database busy failures
  Scenario: A locked database answers BUSY and recovers
    Given a database server with a short busy timeout is running
    When I post a board while the database is locked
    Then the response status is 503
    And the response contains "BUSY"
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    And the response contains "Project"
