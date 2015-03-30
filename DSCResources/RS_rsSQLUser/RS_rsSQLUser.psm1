Add-Type -AssemblyName 'System.DirectoryServices.AccountManagement'
[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null;
$server = new-object Microsoft.SqlServer.Management.Smo.Server("localhost");
$role = New-object Microsoft.SqlServer.Management.Smo.ServerRole($server, "sysAdmin")

function Get-TargetResource
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscredential]$User,
        [Boolean]$Admin = $False,
        [ValidateSet("Windows","SQL")]
        [String]$Auth = "SQL",
        [pscredential]$Credential,
        [ValidateSet("Present", "Absent")]
        [string] $Ensure = "Present"
    )

    #Credential Check: Validating the auth user for creating the Database
    if($psboundparameters.Auth -eq "Windows")
    {
        try{
        if($Credential)
        {
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList ([System.DirectoryServices.AccountManagement.ContextType]::Machine)
            $verifyCredential = ([System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($principalContext, $Credential.username))
            $AdminGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($principalContext, "Administrators")
            $AdminMember = [bool]([System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($principalContext, $Credential.username).IsMemberOf($AdminGroup))
            $GroupSQL = [bool]($role.enumMemberNames().contains("BUILTIN\Administrators"))
            if(($verifyCredential) -and ($AdminMember) -and ($GroupSQL))
            {$CredentialOK = $true}else{
                $CredentialOK = $false;
                Write-Verbose "Credential user information incorrect"
                Write-Verbose " User found: [bool]$verifyCredential /n User is Admin: $AdminMember /n Administrators in sysAdmins: $GroupSQL"
                }
        }else{
            $GroupSQL = [bool]($role.enumMemberNames()| ? { $_ -match "SYSTEM"})
            if($groupSQL)
            {$CredentialOK = $true}else{
                $CredentialOK = $false;
                Write-Verbose "System is not in the sysAdmins role."
                }
            }
        }
        finally
        {
        if ($verifyCredential -ne $null)
        {
            $verifyCredential.Dispose()
            $AdminGroup.Dispose()
        }
        $principalContext.Dispose()
        }
    }
    elseif ($psboundparameters.Auth -eq "SQL")
    {
    
    #Programming notice: The current script does not test at this stage to ensure password is accurate
    #for Credential user.
        try{
        if($Credential)
        {
            $UserSQL = [bool]($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match $Credential.UserName)
            $GroupSQL = [bool]($role.enumMemberNames()| ? {$_ -match $Credential.UserName})
            if(($userSQL) -and ($GroupSQL))
            {$CredentialOK = $true}else{
            $CredentialOK = $false;
            Write-Verbose "Credential information incorrect"
            Write-Verbose " User found: $UserSQL /n User in sysAdmins: $GroupSQL"}
        }elseif(Test-Path "C:\SQL_SA_Password.txt")
        {
            if (($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match "sa"))
            {$CredentialOK = $true}else{$CredentialOK = $false}
        }
        }
        finally{Write-Verbose "Credential Check Result: $CredentialOK"}
    }
    #User Check: Test if User exists and has perm.
    $UserCheck = [bool]($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match $User.UserName)
    $AdminCheck = [bool]($role.enumMemberNames()| ? {$_ -match $User.UserName})
    if(($UserCheck) -and ($AdminCheck -match $Admin)){$Ensure = "Present"}else{$Ensure = "Absent"}

    Return @{
            Name = $Name;
            User = $User.UserName;
            Admin = $AdminCheck;
            Auth = $Auth;
            Credential = $Credential.UserName;
            Ensure = $Ensure
            }
}

function Set-TargetResource
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscredential]$User,
        [Boolean]$Admin = $False,
        [ValidateSet("Windows","SQL")]
        [String]$Auth = "SQL",
        [pscredential]$Credential,
        [ValidateSet("Present", "Absent")]
        [string] $Ensure = "Present"
    )

    if($psboundparameters.Auth -eq "Windows")
    {
        try{
        if($Credential)
        {
            Write-Verbose "Windows Auth with Credentials Specified. Testing Credential rights."
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList ([System.DirectoryServices.AccountManagement.ContextType]::Machine)
            $verifyCredential = ([System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($principalContext, $Credential.username))
            $AdminGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($principalContext, "Administrators")
            $AdminMember = [bool]([System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($principalContext, $Credential.username).IsMemberOf($AdminGroup))
            $GroupSQL = [bool]($role.enumMemberNames().contains("BUILTIN\Administrators"))
            if(($verifyCredential) -and ($AdminMember) -and ($GroupSQL))
            {
                Write-Verbose "Credential test successful. Connecting to SQL with Admin Credentials."
                $server = $null
                $server = new-object Microsoft.SqlServer.Management.Smo.Server("localhost")
                $server.ConnectionContext.ConnectAsUser = $true
                $server.ConnectionContext.LoginSecure = $true
                $server.ConnectionContext.ConnectAsUserName = $Credential.UserName
                $server.ConnectionContext.ConnectAsUserPassword = $Credential.GetNetworkCredential().Password
                Write-Verbose "$server.Loginmode"
            }
        }else{Write-Verbose "Windows Auth without Credentials specified. Using SYSTEM Account."}
        }
        finally
        {
        if ($verifyCredential -ne $null)
        {
            $verifyCredential.Dispose()
            $AdminGroup.Dispose()
        }
        $principalContext.Dispose()
        }
    }
    elseif ($psboundparameters.Auth -eq "SQL")
    {
        if($Credential)
        {
            Write-Verbose "SQL Auth with Credentials Specified. Testing Credential rights."
            $UserSQL = [bool]($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match $Credential.UserName)
            $GroupSQL = [bool]($role.enumMemberNames()| ? {$_ -match $Credential.UserName})
            if(($userSQL) -and ($GroupSQL))
            {
                Write-Verbose "Credential test successful. Connecting to SQL with SQL Credentials."
                $server = $null
                $server = new-object Microsoft.SqlServer.Management.Smo.Server("localhost")
                $server.ConnectionContext.ConnectAsUser = $true
                $server.ConnectionContext.LoginSecure = $false
                $server.ConnectionContext.ConnectAsUserName = $Credential.UserName
                $server.ConnectionContext.ConnectAsUserPassword = $Credential.GetNetworkCredential().Password
                Write-Verbose "$server.Loginmode"
            }
        }elseif(Test-Path "C:\SQL_SA_Password.txt")
        {
            $pass = (Get-Content C:\SQL_SA_Password.txt -Delimiter ' = ')[1]
            if (($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match "sa"))
            {
                Write-Verbose "Connecting to SQL with SA Credentials."
                $server = $null
                $server = new-object Microsoft.SqlServer.Management.Smo.Server("localhost")
                $server.ConnectionContext.ConnectAsUser = $true
                $server.ConnectionContext.LoginSecure = $false
                $server.ConnectionContext.ConnectAsUserName = "sa"
                $server.ConnectionContext.ConnectAsUserPassword =$pass
                Write-Verbose "$server.Loginmode"
            }
        }
    }
    
    # Creating new SQL User Account.
    if(!($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match $User.UserName))
    {
        $login = new-object Microsoft.SqlServer.Management.Smo.Login($server, $User.UserName)
        $login.LoginType = 'SqlLogin'
        $login.PasswordPolicyEnforced = $false
        $login.PasswordExpirationEnabled = $false
        $login.Create($User.GetNetworkCredential().Password)
        if($Admin)
        {
            $role = $null
            $role = New-object Microsoft.SqlServer.Management.Smo.ServerRole($server, "sysAdmin")
            $role.AddMember($User.UserName)
        }
    }
    # Updating password for an exising SQL User Account to match State.
    elseif(($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match $User.UserName))
    {
        $login = new-object Microsoft.SqlServer.Management.Smo.Login($server, $User.UserName)
        $login.ChangePassword($User.GetNetworkCredential().Password, $true, $false)
    }
}

function Test-TargetResource
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscredential]$User,
        [Boolean]$Admin = $False,
        [ValidateSet("Windows","SQL")]
        [String]$Auth = "SQL",
        [pscredential]$Credential,
        [ValidateSet("Present", "Absent")]
        [string] $Ensure = "Present"
    )

    #User Check: Test if User exists and has perm.
    $UserCheck = [bool]($server.Logins | ? LoginType -eq "SqlLogin" | ? Name -match $User.UserName)
    $AdminCheck = [bool]($role.enumMemberNames()| ? {$_ -match $User.UserName})
    if($Ensure = "Present")
    {
        if(($UserCheck) -and ($AdminCheck -match $Admin))
        { return $true } else { return $false }
    }
    if($Ensure = "Absent")
    {
        if(!($UserCheck))
        { return $true } else { return $false }
    }

}


Export-ModuleMember -Function *-TargetResource