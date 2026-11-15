Feature: The web login

  Scenario: With no user the login page is the form that creates the first one
    Given the database server is running
    When I get the page "/login"
    Then the response status is 200
    And the response contains "Create the user"
    And the response does not contain "Sign in"

  Scenario: The first visitor registers and is signed in
    Given the database server is running
    When I register the user "Owner" with the password "Sup3r-secret!"
    Then the response status is 303
    And the response redirects to "/boards"
    And the response sets the session cookie
    And the store has 1 users
    And the store has 1 sessions
    And the store keeps the password of "owner" as a scrypt hash without "Sup3r-secret!"
    When I get the page "/boards" with the session
    Then the response status is 200

  Scenario: The session cookie is HttpOnly, SameSite Lax and not Secure over plain HTTP
    Given the database server is running
    When I sign in
    Then the response header "set-cookie" contains "HttpOnly"
    And the response header "set-cookie" contains "SameSite=Lax"
    And the response header "set-cookie" contains "Max-Age=604800"

  Scenario: Registration is closed once a user exists
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I register the user "intruder" with the password "Sup3r-secret!"
    Then the response status is 403
    And the response contains "Registration is closed"
    And the response sets no cookie
    And the store has 1 users

  Scenario: Once a user exists the login page shows only the sign-in form
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I post to "/logout" with the session
    And I get the page "/login"
    Then the response status is 200
    And the response contains "Sign in"
    And the response does not contain "Create the user"

  Scenario: Two visitors register at once and only one gets in
    Given the database server is running
    When two visitors register at once
    Then the response has 1 sign-ins and 1 refusals
    And the store has 1 users
    And the store has 1 sessions

  Scenario Outline: A password that breaks a rule is refused with the reason
    Given the database server is running
    When I register the user "owner" with the password "<password>"
    Then the response status is 400
    And the response contains "<message>"
    And the response sets no cookie
    And the store has 0 users

    Examples:
      | password           | message                                         |
      | Ab1!               | must be 8 to 16 characters long (it has 4)      |
      | Abcdefgh1!Abcdefgh | must be 8 to 16 characters long (it has 18)     |
      | abcdefg1!          | needs an uppercase letter                       |
      | ABCDEFG1!          | needs a lowercase letter                        |
      | Abcdefgh!          | needs a number                                  |
      | Abcdefg12          | needs a special character                       |

  Scenario: Every broken rule is named at once
    Given the database server is running
    When I register the user "owner" with the password "abc"
    Then the response status is 400
    And the response contains "must be 8 to 16 characters long (it has 3)"
    And the response contains "needs an uppercase letter"
    And the response contains "needs a number"
    And the response contains "needs a special character"

  Scenario Outline: A username or a confirmation that is wrong is refused with the reason
    Given the database server is running
    When I register the user "<username>" with the password "Sup3r-secret!" and the confirmation "<confirmation>"
    Then the response status is 400
    And the response contains "<message>"
    And the store has 0 users

    Examples:
      | username | confirmation  | message                                  |
      | ab       | Sup3r-secret! | The username must be 3 to 32 characters  |
      | a b c    | Sup3r-secret! | The username may have only letters       |
      | owner    | Other-pass1!  | The two passwords do not match           |

  Scenario: A registered user signs in with the password and signs out
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I post to "/logout" with the session
    Then the response status is 303
    And the response redirects to "/login"
    And the response clears the session cookie
    And the store has 0 sessions
    When I sign in as "Owner" with the password "Sup3r-secret!"
    Then the response status is 303
    And the response redirects to "/boards"
    And the response sets the session cookie
    When I get the page "/boards" with the session
    Then the response status is 200

  Scenario: A copy of the cookie is no good after signing out
    Given the database server is running
    When I sign in
    And I post to "/logout" with the session
    And I get the page "/boards" with the session
    Then the response status is 302
    And the response redirects to "/login"

  Scenario: A session that has ended is no good
    Given the database server is running
    When I sign in
    And the sessions of the store have ended
    And I get the page "/boards" with the session
    Then the response status is 302
    And the response redirects to "/login"

  Scenario Outline: A wrong password and an unknown user get the same answer
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I sign in as "<username>" with the password "<password>"
    Then the response status is 401
    And the response contains "Invalid username or password."
    And the response sets no cookie

    Examples:
      | username | password      |
      | owner    | Wrong-pass1!  |
      | nobody   | Sup3r-secret! |
      |          |               |

  Scenario: The API key does not sign in to the web
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I sign in as "owner" with the password "01234567890123456789012345678901"
    Then the response status is 401
    And the response sets no cookie

  Scenario: Too many wrong tries are refused, even with the right password
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I try to sign in 5 times as "owner" with the password "Wrong-pass1!"
    Then the response status is 401
    When I try to sign in 1 times as "owner" with the password "Wrong-pass1!"
    Then the response status is 429
    And the response has the header "retry-after"
    When I sign in as "owner" with the password "Sup3r-secret!"
    Then the response status is 429
    And the response sets no cookie

  Scenario: A form from another site cannot sign out the user
    Given the database server is running
    When I sign in
    And I post to "/logout" with the cookie and the origin "https://evil.example"
    Then the response status is 403
    When I get the page "/boards" with the session
    Then the response status is 200

  Scenario: A form from another site cannot sign in or register
    Given the database server is running
    When I post to "/register" with the cookie and the origin "https://evil.example"
    Then the response status is 403
    And the store has 0 users

  Scenario: The CLI and the API key keep working with a user registered
    Given the database server is running
    When I register the user "owner" with the password "Sup3r-secret!"
    And I get "/api/boards" with key "01234567890123456789012345678901"
    Then the response status is 200
    When I get "/api/boards" with key "wrong"
    Then the response status is 401
    When I run kanban "board create Project --slug project"
    Then kanban exits with code 0
    When I run kanban "board list"
    Then kanban exits with code 0
    And kanban output contains "project"
