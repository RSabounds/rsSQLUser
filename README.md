rsSQLUser
=====

This module allows for the creation or password management of a SQL user account using a SQL or Windows Authenticated connection to the instance. Options will allow for the following:

Windows Auth: create user using a specified Windows Account
SQL Auth: create user using a specified SQL Account
Admin: Will set the user as SysAdmin role in SQL
Ensure: Present: Create or maintain password for user | Absent: Remove user if found

::Schema::
User: <PSCredential>
Admin: <Boolean (True|False)>
Auth: <Switch (Windows|SQL)> (Default: SQL)
Credential: <PSCredential> (Default: Read SA password file)
Ensure: <Switch (Present|Absent)>

```PoSh
rsSQLUser myUser
{
    User = $Credentials.AppUser
    Admin = $false
    Auth = "Windows"
    Credential = "$Credentials.AdminUser"
    Ensure = "Present"
}
```

