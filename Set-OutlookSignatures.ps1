<#
  .SYNOPSIS
  Central Outlook text signature management and deployment script.

  .DESCRIPTION
  Set-OutlookSignatures.ps1 downloads centrally stored signatures, replaces variables, optionally sets default signatures.
  Signatures can be applied to all (mailbox) users, specific groups or specific mail addresses.
  Signature templates can be assigned time ranges within which they are valid.
  Signatures are also set in Outlook Web for the currently logged-on user.

  .LINK
  Online help: https://github.com/GruberMarkus/Set-OutlookSignatures

  .LINK
  License and copyright: https://github.com/GruberMarkus/Set-OutlookSignatures/blob/main/license.txt

  .PARAMETER SignatureTemplatePath
  Path to centrally managed signature templates.
  Local and remote paths are supported.
  Local paths can be absolute ('C:\Signature templates') or relative to the script path ('.\Signature templates').
  WebDAV paths are supported (https only): 'https://server.domain/SignatureSite/SignatureTemplates' or '\\server.domain@SSL\SignatureSite\SignatureTemplates'
  Default value: '.\Signature templates'

  .PARAMETER ReplacementVariableConfigFile
  Path to a replacement variable config file.
  Local and remote paths are supported.
  Local paths can be absolute ('C:\Signature templates') or relative to the script path ('.\Signature templates').
  WebDAV paths are supported (https only): 'https://server.domain/SignatureSite/SignatureTemplates' or '\\server.domain@SSL\SignatureSite\SignatureTemplates'
  Default value: '.\config\default replacement variables.txt'

  .PARAMETER DomainsToCheckForGroups
  List of domains/forests to check for group membership across trusts.
  If the first entry in the list is '*', all outgoing and bidirectional trusts in the current user's forest are considered.
  If a string starts with a minus or dash ("-domain-a.local"), the domain after the dash or minus is removed from the list.
  Default value: '*'

  .PARAMETER DeleteUserCreatedSignatures
  Shall the script delete signatures which were created by the user itself?
  The script always deletes signatures which were deployed by the script earlier, but are no longer available in the central repository.
  Default value: $false

  .PARAMETER SetCurrentUserOutlookWebSignature
  Shall the script set the Outlook Web signature of the currently logged on user?
  Default value: $true

  .PARAMETER AdditionalSignaturePath
  An additional path that the signatures shall be copied to.
  Ideally, this path is available on all devices of the user, for example via OneDrive.
  This way, the user can easily copy-paste his preferred preconfigured signature for use in a mail app not support by this script, such as Microsoft Outlook Mobile, Apple Mail, Google Gmail or Samsung Email.
  Default value: "$($env:OneDriveCommercial)\Outlook signatures"

  .INPUTS
  None. You cannot pipe objects to Set-OutlookSignatures.ps1.

  .OUTPUTS
  Set-OutlookSignatures.ps1 outputs the current activities, warnings and error messages to the standard output streams.

  .EXAMPLE
  PS> .\Set-OutlookSignatures.ps1

  .EXAMPLE
  PS> .\Set-OutlookSignatures.ps1 -SignatureTemplatePath '\\internal.example.com\share\Signature Templates'

  .EXAMPLE
  PS> .\Set-OutlookSignatures.ps1 -SignatureTemplatePath '\\internal.example.com\share\Signature Templates' -DomainsToCheckForGroups '*', '-internal-test.example.com'

  .EXAMPLE
  PS> .\Set-OutlookSignatures.ps1 -SignatureTemplatePath '\\internal.example.com\share\Signature Templates' -DomainsToCheckForGroups 'internal-test.example.com', 'company.b.com'

  .NOTES
  Script : Set-OutlookSignatures.ps1
  Version: 1.4.0
  Author : Markus Gruber
  License: MIT License (see license.txt for details and copyright)
  Web    : https://github.com/GruberMarkus/Set-OutlookSignatures
#>


[CmdletBinding()]

Param(
    # Path to centrally managed signature templates
    #   Local and remote paths are supported
    #     Local paths can be absolute ('C:\Signature templates') or relative to the script path ('.\Signature templates')
    #   WebDAV paths are supported (https only)
    #     'https://server.domain/SignatureSite/SignatureTemplates' or '\\server.domain@SSL\SignatureSite\SignatureTemplates'
    #   The currently logged-on user needs at least read access to the path
    [ValidateNotNullOrEmpty()][string]$SignatureTemplatePath = '.\Signature templates',

    # Path to a replacement variable config file.
    #   Local and remote paths are supported
    #     Local paths can be absolute ('C:\Signature templates') or relative to the script path ('.\Signature templates')
    #   WebDAV paths are supported (https only)
    #     'https://server.domain/SignatureSite/SignatureTemplates' or '\\server.domain@SSL\SignatureSite\SignatureTemplates'
    #   The currently logged-on user needs at least read access to the path
    [ValidateNotNullOrEmpty()][string]$ReplacementVariableConfigFile = '.\config\default replacement variables.txt',

    # List of domains/forests to check for group membership across trusts
    #   If the first entry in the list is '*', all outgoing and bidirectional trusts in the current user's forest are considered
    #   If a string starts with a minus or dash ("-domain-a.local"), the domain after the dash or minus is removed from the list
    [string[]]$DomainsToCheckForGroups = ('*'),

    # Shall the script delete signatures which were created by the user itself?
    #   The script always deletes signatures which were deployed by the script earlier, but are no longer available in the central repository.
    [bool]$DeleteUserCreatedSignatures = $false,

    # Shall the script set the Outlook Web signature of the currently logged on user?
    [bool]$SetCurrentUserOutlookWebSignature = $true,
    
    # An additional path that the signatures shall be copied to
    [ValidateNotNullOrEmpty()][string]$AdditionalSignaturePath = "$($env:OneDriveCommercial)\Outlook signatures"
)


function GetVersionInfo {
    $notes = [Ordered]@{}
    $lines = (((Get-Help -Full $PSCommandPath).alertSet.alert.Text) -split '\r?\n').Trim()

    foreach ($line in $lines) {
        if (!$line) {
            continue
        }

        $name = $null

        # Split line by the first colon (:) character.
        if ($line.Contains(':')) {
            $nameValue = $null
            $nameValue = ($line -split ':', 2).Trim()
            $notes[$nameValue[0]] = $nameValue[1].trim()
        }
    }

    return $notes
}


function Set-Signatures {
    Write-Host "    '$($Signature.Name)'"

    $SignatureFileAlreadyDone = ($global:SignatureFilesDone -contains $($Signature.Name))
    if ($SignatureFileAlreadyDone) {
        Write-Host '      File already processed before' -ForegroundColor Yellow
    } else {
        $global:SignatureFilesDone += $($Signature.Name)
    }

    if ($SignatureFileAlreadyDone -eq $false) {
        Write-Host '      Copy file and open it in Word'

        $path = $(Join-Path -Path $env:temp -ChildPath (New-Guid).guid).tostring() + '.docx'

        try {
            Copy-Item -LiteralPath $Signature.Name -Destination $path -Force
        } catch {
            Write-Host '        Error copying file. Skipping signature.' -ForegroundColor Red
            continue
        }

        $Signature.value = $([System.IO.Path]::ChangeExtension($($Signature.value), '.htm'))
        $global:SignatureFilesDone += $Signature.Value

        $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdOpenFormat], 'wdOpenFormatAuto')
        $COMWord.Documents.Open($path, $false) | Out-Null

        Write-Host '      Replace variables'
        # Replace pictures in Shapes and InlineShapes
        foreach ($image in ($ComWord.ActiveDocument.InlineShapes + $ComWord.ActiveDocument.InlineShapes)) {
            if ($null -ne $image.linkformat.sourcefullname) {
                ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$') | ForEach-Object {
                    if ((((Split-Path -Path $image.linkformat.sourcefullname -Leaf).contains($_)) -or (($image.alternativetext).contains($_)))) {
                        if ($null -ne $ReplaceHash[$_]) {
                            $ImageAlternativeTextOriginal = $image.AlternativeText
                            $image.linkformat.sourcefullname = (Join-Path -Path $env:temp -ChildPath ($_ + '.jpeg'))
                            $image.alternativetext = $ImageAlternativeTextOriginal.replace($_, '')
                        }
                    } elseif (((Split-Path -Path $image.linkformat.sourcefullname -Leaf).contains(($_[-999..-2] -join '') + 'DELETEEMPTY$')) -or ($image.alternativetext.contains(($_[-999..-2] -join '') + 'DELETEEMPTY$'))) {
                        if ($null -ne $ReplaceHash[$_]) {
                            $ImageAlternativeTextOriginal = $image.AlternativeText
                            $image.linkformat.sourcefullname = (Join-Path -Path $env:temp -ChildPath ($_ + '.jpeg'))
                            $image.alternativetext = $ImageAlternativeTextOriginal.replace((($_[-999..-2] -join '') + 'DELETEEMPTY$'), '')
                        } else {
                            $image.delete()
                        }
                    }
                }
            }

            # Setting the values in word is very slow, so we use temporay variables
            $tempImageAlternativeText = $image.alternativetext
            $tempImageHyperlinkName = $image.hyperlink.Name
            $tempImageHyperlinkAddress = $image.hyperlink.Address
            $tempImageHyperlinkAddressOld = $image.hyperlink.AddressOld
            $tempImageHyperlinkSubAddress = $image.hyperlink.SubAddress
            $tempImageHyperlinkSubaddressOld = $image.hyperlink.SubAddressOld
            $tempImageHyperlinkEmailSubject = $image.hyperlink.EmailSubject
            $tempImageHyperlinkScreenTip = $image.hyperlink.ScreenTip

            foreach ($replaceKey in $replaceHash.Keys) {
                if ($replaceKey -notin ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$', '$CURRENTMAILBOXMANAGERPHOTODELETEEMPTY$', '$CURRENTMAILBOXPHOTODELETEEMPTY$', '$CURRENTUSERMANAGERPHOTODELETEEMPTY$', '$CURRENTUSERPHOTODELETEEMPTY$')) {
                    if ($null -ne $tempimagealternativetext) {
                        $tempimagealternativetext = $tempimagealternativetext.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkName) {
                        $tempimagehyperlinkname = $tempimagehyperlinkname.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkAddress) {
                        $tempimagehyperlinkAddress = $tempimagehyperlinkAddress.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkAddressOld) {
                        $tempimagehyperlinkAddressOld = $tempimagehyperlinkAddressOld.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkSubAddress) {
                        $tempimagehyperlinkSubAddress = $tempimagehyperlinkSubAddress.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkSubAddressOld) {
                        $tempimagehyperlinkSubAddressOld = $tempimagehyperlinkSubAddressOld.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkEmailSubject) {
                        $tempimagehyperlinkEmailSubject = $tempimagehyperlinkEmailSubject.replace($replaceKey, $replaceHash.replaceKey)
                    }
                    if ($null -ne $tempimagehyperlinkScreenTip) {
                        $tempimagehyperlinkScreenTip = $tempimagehyperlinkScreenTip.replace($replaceKey, $replaceHash.replaceKey)
                    }
                }
            }

            if ($null -ne $tempimagealternativetext) {
                $image.alternativetext = $tempImageAlternativeText
            }
            if ($null -ne $tempimagehyperlinkName) {
                $image.hyperlink.Name = $tempImageHyperlinkName
            }
            if ($null -ne $tempimagehyperlinkAddress) {
                $image.hyperlink.Address = $tempImageHyperlinkAddress
            }
            if ($null -ne $tempimagehyperlinkAddressOld) {
                $image.hyperlink.AddressOld = $tempImageHyperlinkAddressOld
            }
            if ($null -ne $tempimagehyperlinkSubAddress) {
                $image.hyperlink.SubAddress = $tempImageHyperlinkSubAddress
            }
            if ($null -ne $tempimagehyperlinkSubAddressOld) {
                $image.hyperlink.SubAddressOld = $tempImageHyperlinkSubaddressOld
            }
            if ($null -ne $tempimagehyperlinkEmailSubject) {
                $image.hyperlink.EmailSubject = $tempImageHyperlinkEmailSubject
            }
            if ($null -ne $tempimagehyperlinkScreenTip) {
                $image.hyperlink.ScreenTip = $tempImageHyperlinkScreenTip
            }
        }

        # Replace non-picture related variables
        $wdFindContinue = 1
        $MatchCase = $true
        $MatchWholeWord = $true
        $MatchWildcards = $False
        $MatchSoundsLike = $False
        $MatchAllWordForms = $False
        $Forward = $True
        $Wrap = $wdFindContinue
        $Format = $False
        $wdFindContinue = 1
        $ReplaceAll = 2

        # Replace in current view (show or hide field codes)
        foreach ($replaceKey in $replaceHash.Keys) {
            if ($replaceKey -notin ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$', '$CURRENTMAILBOXMANAGERPHOTODELETEEMPTY$', '$CURRENTMAILBOXPHOTODELETEEMPTY$', '$CURRENTUSERMANAGERPHOTODELETEEMPTY$', '$CURRENTUSERPHOTODELETEEMPTY$')) {
                $FindText = $replaceKey
                $ReplaceWith = $replaceHash.$replaceKey
                $COMWord.Selection.Find.Execute($FindText, $MatchCase, $MatchWholeWord, `
                        $MatchWildcards, $MatchSoundsLike, $MatchAllWordForms, $Forward, `
                        $Wrap, $Format, $ReplaceWith, $ReplaceAll) | Out-Null
            }
        }

        # Invert current view (show or hide field codes)
        # This is neccessary to be able to replace variables in hyperlinks and quicktips of hyperlinks
        $COMWord.ActiveDocument.ActiveWindow.View.ShowFieldCodes = (-not $COMWord.ActiveDocument.ActiveWindow.View.ShowFieldCodes)
        foreach ($replaceKey in $replaceHash.Keys) {
            if ($replaceKey -notin ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$', '$CURRENTMAILBOXMANAGERPHOTODELETEEMPTY$', '$CURRENTMAILBOXPHOTODELETEEMPTY$', '$CURRENTUSERMANAGERPHOTODELETEEMPTY$', '$CURRENTUSERPHOTODELETEEMPTY$')) {
                $FindText = $replaceKey
                $ReplaceWith = $replaceHash.$replaceKey
                $COMWord.Selection.Find.Execute($FindText, $MatchCase, $MatchWholeWord, `
                        $MatchWildcards, $MatchSoundsLike, $MatchAllWordForms, $Forward, `
                        $Wrap, $Format, $ReplaceWith, $ReplaceAll) | Out-Null
            }
        }

        # Restore original view
        $COMWord.ActiveDocument.ActiveWindow.View.ShowFieldCodes = (-not $COMWord.ActiveDocument.ActiveWindow.View.ShowFieldCodes)

        # Exports
        Write-Host '      Save as filtered .HTM file'
        $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdSaveFormat], 'wdFormatFilteredHTML')
        $path = $([System.IO.Path]::ChangeExtension($path, '.htm'))
        $COMWord.ActiveDocument.Weboptions.encoding = 65001
        $COMWord.ActiveDocument.SaveAs($path, $saveFormat)

        Write-Host '      Save as .TXT file'
        $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdSaveFormat], 'wdFormatUnicodeText')
        $COMWord.ActiveDocument.TextEncoding = 1200
        $path = $([System.IO.Path]::ChangeExtension($path, '.txt'))
        $COMWord.ActiveDocument.SaveAs($path, $saveFormat)

        Write-Host '      Save as .RTF file'
        $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdSaveFormat], 'wdFormatRTF')
        $path = $([System.IO.Path]::ChangeExtension($path, '.rtf'))
        $COMWord.ActiveDocument.SaveAs($path, $saveFormat)
        $COMWord.ActiveDocument.Close($false)

        # RTF files with embedded images get really huge
        # See https://support.microsoft.com/kb/224663 for a system-wide workaround
        # The following workaround is from https://answers.microsoft.com/en-us/msoffice/forum/msoffice_word-mso_mac-mso_mac2011/huge-rtf-files-solved-on-windows-but-searching-for/58e54b37-cfd0-4a07-ac62-1cfc2769cad5
        $openFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdOpenFormat], 'wdOpenFormatUnicodeText')
        $COMWord.Documents.Open($path, $false, $false, $false, '', '', $true, '', '', $openFormat) | Out-Null
        $FindText = '\{\\nonshppict*\}\}'
        $ReplaceWith = ''
        $COMWord.Selection.Find.Execute($FindText, $MatchCase, $MatchWholeWord, `
                $true, $MatchSoundsLike, $MatchAllWordForms, $Forward, `
                $Wrap, $Format, $ReplaceWith, $ReplaceAll) | Out-Null
        $COMWord.ActiveDocument.Save()
        $COMWord.ActiveDocument.Close($false)

        Write-Host '      Embed local files in .HTM file and add marker'
        $path = $([System.IO.Path]::ChangeExtension($path, '.htm'))

        $tempFileContent = Get-Content -LiteralPath $path -Raw -Encoding UTF8

        if ($tempFileContent -notlike "*$HTMLMarkerTag*") {
            if ($tempFileContent -like '*<head>*') {
                $tempFileContent = $tempFileContent -ireplace ('<HEAD>', ('<head>' + $HTMLMarkerTag))
            } else {
                $tempFileContent = $tempFileContent -ireplace ('<HTML>', ('<HTML><head>' + $HTMLMarkerTag + '</head>'))
            }
        }

        $src = @()
        ([regex]'(?i)src="(.*?)"').Matches($tempFileContent) | ForEach-Object {
            $src += $_.Groups[0].Value
            $src += (Join-Path -Path (Split-Path -Path $path -Parent) -ChildPath ([uri]::UnEscapeDataString($_.Groups[1].Value)))
        }

        for ($x = 0; $x -lt $src.count; $x = $x + 2) {
            if ($src[$x].StartsWith('src="data:')) {
            } elseif (Test-Path -LiteralPath $src[$x + 1] -PathType leaf) {
                $fmt = $null
                switch ((Get-ChildItem -LiteralPath $src[$x + 1]).Extension) {
                    '.apng' {
                        $fmt = 'data:image/apng;base64,'
                    }
                    '.avif' {
                        $fmt = 'data:image/avif;base64,'
                    }
                    '.gif' {
                        $fmt = 'data:image/gif;base64,'
                    }
                    '.jpg' {
                        $fmt = 'data:image/jpeg;base64,'
                    }
                    '.jpeg' {
                        $fmt = 'data:image/jpeg;base64,'
                    }
                    '.jfif' {
                        $fmt = 'data:image/jpeg;base64,'
                    }
                    '.pjpeg' {
                        $fmt = 'data:image/jpeg;base64,'
                    }
                    '.pjp' {
                        $fmt = 'data:image/jpeg;base64,'
                    }
                    '.png' {
                        $fmt = 'data:image/png;base64,'
                    }
                    '.svg' {
                        $fmt = 'data:image/svg+xml;base64,'
                    }
                    '.webp' {
                        $fmt = 'data:image/webp;base64,'
                    }
                    '.css' {
                        $fmt = 'data:text/css;base64,'
                    }
                    '.less' {
                        $fmt = 'data:text/css;base64,'
                    }
                    '.js' {
                        $fmt = 'data:text/javascript;base64,'
                    }
                    '.otf' {
                        $fmt = 'data:font/otf;base64,'
                    }
                    '.sfnt' {
                        $fmt = 'data:font/sfnt;base64,'
                    }
                    '.ttf' {
                        $fmt = 'data:font/ttf;base64,'
                    }
                    '.woff' {
                        $fmt = 'data:font/woff;base64,'
                    }
                    '.woff2' {
                        $fmt = 'data:font/woff2;base64,'
                    }
                }
                if ($fmt) {
                    $tempFileContent = $tempFileContent.replace( `
                            $src[$x], `
                        ('src="' + $fmt + [Convert]::ToBase64String([IO.File]::ReadAllBytes($src[$x + 1])) + '"') `
                    )

                } else {
                }
            } else {
            }
        }

        $tempFileContent | Out-File -LiteralPath $path -Encoding UTF8 -Force

        $SignaturePaths | ForEach-Object {
            Write-Host "      Copy signature files to '$_'"
            Copy-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.htm')) -Destination ('\\?\' + (Join-Path -Path $($_ -replace [regex]::escape('\\?\'), '') -ChildPath $([System.IO.Path]::ChangeExtension($Signature.Value, '.htm')))) -Force
            Copy-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.rtf')) -Destination ('\\?\' + (Join-Path -Path $($_ -replace [regex]::escape('\\?\'), '') -ChildPath $([System.IO.Path]::ChangeExtension($Signature.Value, '.rtf')))) -Force
            Copy-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.txt')) -Destination ('\\?\' + (Join-Path -Path $($_ -replace [regex]::escape('\\?\'), '') -ChildPath $([System.IO.Path]::ChangeExtension($Signature.Value, '.txt')))) -Force
        }
        Remove-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.docx')) -Force -Recurse
        Remove-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.htm')) -Force -Recurse
        Remove-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.rtf')) -Force -Recurse
        Remove-Item -LiteralPath $([System.IO.Path]::ChangeExtension($path, '.txt')) -Force -Recurse
        Foreach ($x in (Get-ChildItem -Path ("$($env:temp)\*" + [System.IO.Path]::GetFileNameWithoutExtension($path) + '*') -Directory).FullName) {
            Remove-Item -LiteralPath $x -Force -Recurse
        }
    }

    # Set default signature for new mails
    if ($SignatureFilesDefaultNew.contains('' + $Signature.name + '')) {
        for ($j = 0; $j -lt $MailAddresses.count; $j++) {
            if ($MailAddresses[$j] -ieq $MailAddresses[$AccountNumberRunning]) {
                Write-Host '      Set signature as default for new messages'
                Set-ItemProperty -Path $RegistryPaths[$j] -Name 'New Signature' -Type String -Value (($Signature.value -split '\.' | Select-Object -SkipLast 1) -join '.') -Force
            }
        }
    }

    # Set default signature for replies and forwarded mails
    if ($SignatureFilesDefaultReplyFwd.contains($Signature.name)) {
        for ($j = 0; $j -lt $MailAddresses.count; $j++) {
            if ($MailAddresses[$j] -ieq $MailAddresses[$AccountNumberRunning]) {
                Write-Host '      Set signature as default for reply/forward messages'
                Set-ItemProperty -Path $RegistryPaths[$j] -Name 'Reply-Forward Signature' -Type String -Value (($Signature.value -split '\.' | Select-Object -SkipLast 1) -join '.') -Force
            }
        }
    }
}


function CheckADConnectivity {
    param (
        [array]$CheckDomains,
        [string]$CheckProtocolText,
        [string]$Indent
    )
    [void][runspacefactory]::CreateRunspacePool()
    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, 10)
    $PowerShell = [powershell]::Create()
    $PowerShell.RunspacePool = $RunspacePool
    $RunspacePool.Open()

    for ($DomainNumber = 0; $DomainNumber -lt $CheckDomains.count; $DomainNumber++) {
        if ($($CheckDomains[$DomainNumber]) -eq '') {
            continue
        }

        $PowerShell = [powershell]::Create()
        $PowerShell.RunspacePool = $RunspacePool

        [void]$PowerShell.AddScript( {
                Param (
                    [string]$CheckDomain,
                    [string]$CheckProtocolText
                )
                $DebugPreference = 'Continue'
                Write-Debug "Start(Ticks) = $((Get-Date).Ticks)"
                Write-Output "$CheckDomain"
                $Search = New-Object DirectoryServices.DirectorySearcher
                $Search.PageSize = 1000
                $Search.searchroot = New-Object System.DirectoryServices.DirectoryEntry("$($CheckProtocolText)://$CheckDomain")
                $Search.filter = '(objectclass=user)'
                try {
                    $UserAccount = ([ADSI]"$(($Search.FindOne()).path)")
                    Write-Output 'QueryPassed'
                } catch {
                    Write-Output 'QueryFailed'
                }
            }).AddArgument($($CheckDomains[$DomainNumber])).AddArgument($CheckProtocolText)
        $Object = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        $Handle = $PowerShell.BeginInvoke($Object, $Object)
        $temp = '' | Select-Object PowerShell, Handle, Object, StartTime, Done
        $temp.PowerShell = $PowerShell
        $temp.Handle = $Handle
        $temp.Object = $Object
        $temp.StartTime = $null
        $temp.Done = $false
        [void]$jobs.Add($Temp)
    }
    while (($jobs.Done | Where-Object { $_ -eq $false }).count -ne 0) {
        $jobs | ForEach-Object {
            if (($null -eq $_.StartTime) -and ($_.Powershell.Streams.Debug[0].Message -match 'Start')) {
                $StartTicks = $_.powershell.Streams.Debug[0].Message -replace '[^0-9]'
                $_.StartTime = [Datetime]::MinValue + [TimeSpan]::FromTicks($StartTicks)
            }

            if ($null -ne $_.StartTime) {
                if ((($_.handle.IsCompleted -eq $true) -and ($_.Done -eq $false)) -or (($_.Done -eq $false) -and ((New-TimeSpan -Start $_.StartTime -End (Get-Date)).TotalSeconds -ge 5))) {
                    $data = $_.Object[0..$(($_.object).count - 1)]
                    Write-Host "$Indent$($data[0])"
                    if ($data -icontains 'QueryPassed') {
                        Write-Host "$Indent  $CheckProtocolText query successful."
                        $returnvalue = $true
                    } else {
                        Write-Host "$Indent  $CheckProtocolText query failed, removing domain from list." -ForegroundColor Red
                        Write-Host "$Indent  If this error is permanent, check firewalls and AD trust. Consider using parameter DomainsToCheckForGroups." -ForegroundColor Red
                        $DomainsToCheckForGroups.remove($data[0])
                        $returnvalue = $false
                    }
                    $_.Done = $true
                }
            }
        }
    }
    return $returnvalue
}


function CheckPath([string]$path) {
    if ($path.StartsWith('https://', 'CurrentCultureIgnoreCase')) {
        $path = (([uri]::UnescapeDataString($path) -ireplace ('https://', '\\')) -replace ('(.*?)/(.*)', '${1}@SSL\$2')) -replace ('/', '\')
        $path = $path -replace [regex]::escape('\\'), '\\?\UNC\'
    } else {
        $path = ('\\?\' + $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path))
    }

    if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) {
        # Reconnect already connected network drives at the OS level
        # New-PSDrive is not enough for this
        Get-CimInstance Win32_NetworkConnection | ForEach-Object {
            & net use $_.LocalName $_.RemoteName 2>&1 | Out-Null
        }

        if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) {
            # Connect network drives
            '`r`n' | & net use "$path" 2>&1 | Out-Null
            try {
                (Test-Path -LiteralPath $path -ErrorAction Stop) | Out-Null
            } catch {
                if ($_.CategoryInfo.Category -eq 'PermissionDenied') {
                    & net use "$path" 2>&1
                }
            }
            & net use "$path" /d 2>&1 | Out-Null
        }

        if (($path -ilike '*@ssl\*') -and (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue))) {
            # Add site to trusted sites in internet options
            New-Item ('HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\' + (New-Object System.Uri -ArgumentList ($path -ireplace ('@SSL', ''))).Host) -Force | New-ItemProperty -Name * -Value 1 -Type DWORD -Force | Out-Null

            # Open site in new IE process
            $oIE = New-Object -com InternetExplorer.Application
            $oIE.Visible = $false
            $oIE.Navigate2('https://' + ((($path -ireplace ('@SSL', '')).replace('\\', '')).replace('\', '/')))
            $oIE = $null

            # Wait until an IE tab with the corresponding URL is open
            $app = New-Object -com shell.application
            $i = 0
            while ($i -lt 1) {
                $app.windows() | Where-Object { $_.LocationURL -like ('*' + ([uri]::EscapeUriString(((($path -ireplace ('@SSL', '')).replace('\\', '')).replace('\', '/')))) + '*') } | ForEach-Object {
                    $i = $i + 1
                }
                Start-Sleep -Milliseconds 50
            }

            # Wait until the corresponding URL is fully loaded, then close the tab
            $app.windows() | Where-Object { $_.LocationURL -like ('*' + ([uri]::EscapeUriString(((($path -ireplace ('@SSL', '')).replace('\\', '')).replace('\', '/')))) + '*') } | ForEach-Object {
                while ($_.busy) {
                    Start-Sleep -Milliseconds 50
                }
                $_.quit()
            }

            $app = $null

        }
    }

    if ((Test-Path -LiteralPath $path) -eq $false) {
        Write-Host ": Problem connecting to or reading from folder '$path'. Exiting." -ForegroundColor Red
        exit 1
    } else {
        Write-Host
    }
}


Clear-Host


Write-Host 'Script started'

Write-Host '  Script notes'
$versionInfo = GetVersionInfo
foreach ($key in $versionInfo.keys) {
    Write-Host "    $($key): $($versionInfo[$key])"
}

Write-Host '  Check parameters and script environment'
Set-Location $PSScriptRoot | Out-Null
$Search = New-Object DirectoryServices.DirectorySearcher
$Search.PageSize = 1000
$jobs = New-Object System.Collections.ArrayList

Write-Host "    Script name: '$PSCommandPath'"
Write-Host "    Script path: '$PSScriptRoot'"
Write-Host "    SignatureTemplatePath: '$SignatureTemplatePath'" -NoNewline
CheckPath $SignatureTemplatePath
Write-Host "    ReplacementVariableConfigFile: '$ReplacementVariableConfigFile'" -NoNewline
CheckPath $ReplacementVariableConfigFile
Write-Host ('    DomainsToCheckForGroups: ' + ('''' + $($DomainsToCheckForGroups -join ''', ''') + ''''))
Write-Host "    DeleteUserCreatedSignatures: '$DeleteUserCreatedSignatures'"
Write-Host "    SetCurrentUserOutlookWebSignature: '$SetCurrentUserOutlookWebSignature'"
Write-Host "    AdditionalSignaturePath: '$AdditionalSignaturePath'"

if (($ExecutionContext.SessionState.LanguageMode) -ine 'FullLanguage') {
    Write-Host "This PowerShell session is in $($ExecutionContext.SessionState.LanguageMode) mode, not FullLanguage mode." -ForegroundColor Red
    Write-Host 'Base64 conversion not possible. Exiting.' -ForegroundColor Red
    exit 1
}


Write-Host '  Check Outlook version and profile'
try {
    $OutlookRegistryVersion = [System.Version]::Parse(((((Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\Outlook.Application\CurVer').'(default)' -ireplace 'Outlook.Application.', '') + '.0.0.0.0') -split '\.')[0..3] -join '.')
} catch {
    Write-Host 'Outlook not installed or not working correctly. Exiting.' -ForegroundColor Red
    exit 1
}

if ($OutlookRegistryVersion.major -gt 16) {
    Write-Host "Outlook version $OutlookRegistryVersion is newer than 16 and not yet known. Please inform your administrator. Exiting." -ForegroundColor Red
} elseif ($OutlookRegistryVersion.major -eq 16) {
    $OutlookRegistryVersion = '16.0'
} elseif ($OutlookRegistryVersion.major -eq 15) {
    $OutlookRegistryVersion = '15.0'
} elseif ($OutlookRegistryVersion.major -eq 14) {
    $OutlookRegistryVersion = '14.0'
} else {
    Write-Host "Outlook version $OutlookRegistryVersion is below minimum required version 14 (Outlook 2010). Exiting." -ForegroundColor Red
    exit 1
}

$OutlookDefaultProfile = (Get-ItemProperty "hkcu:\software\microsoft\office\$OutlookRegistryVersion\Outlook").DefaultProfile


$HTMLMarkerTag = '<meta name=data-SignatureFileInfo content="Set-OutlookSignatures.ps1">'


Write-Host 'Enumerate domains'
$x = $DomainsToCheckForGroups
[System.Collections.ArrayList]$DomainsToCheckForGroups = @()

# Users own domain/forest is always included
$y = ([ADSI]'LDAP://RootDSE').rootDomainNamingContext -replace ('DC=', '') -replace (',', '.')
if ($y -ne '') {
    Write-Host "  Current user forest: $y"
    $DomainsToCheckForGroups += $y
} else {
    Write-Host '  Problem connecting to Active Directory, or user is a local user. Exiting.' -ForegroundColor Red
    exit 1
}

# Other domains - either the list provided, or all outgoing and bidirectional trusts
if ($x[0] -eq '*') {
    $Search.SearchRoot = "GC://$($DomainsToCheckForGroups[0])"
    $Search.Filter = '(ObjectClass=trustedDomain)'

    $Search.FindAll() | ForEach-Object {
        # DNS name of this side of the trust (could be the root domain or any subdomain)
        # $TrustOrigin = ($_.properties.distinguishedname -split ',DC=')[1..999] -join '.'

        # DNS name of the other side of the trust (could be the root domain or any subdomain)
        # $TrustName = $_.properties.name

        # Domain SID of the other side of the trust
        # $TrustNameSID = (New-Object system.security.principal.securityidentifier($($_.properties.securityidentifier), 0)).tostring()

        # Trust direction
        # https://docs.microsoft.com/en-us/dotnet/api/system.directoryservices.activedirectory.trustdirection?view=net-5.0
        # $TrustDirectionNumber = $_.properties.trustdirection

        # Trust type
        # https://docs.microsoft.com/en-us/dotnet/api/system.directoryservices.activedirectory.trusttype?view=net-5.0
        # $TrustTypeNumber = $_.properties.trusttype

        # Trust attributes
        # https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/e9a2d23c-c31e-4a6f-88a0-6646fdb51a3c
        # $TrustAttributesNumber = $_.properties.trustattributes

        # Which domains does the current user have access to?
        # No intra-forest trusts, only bidirectional trusts and outbound trusts

        if (($($_.properties.trustattributes) -ne 32) -and (($($_.properties.trustdirection) -eq 2) -or ($($_.properties.trustdirection) -eq 3)) ) {
            Write-Host "  Trusted domain: $($_.properties.name)"
            $DomainsToCheckForGroups += $_.properties.name
        }
    }
}

for ($a = 0; $a -lt $x.Count; $a++) {
    if (($a -eq 0) -and ($x[$a] -ieq '*')) {
        continue
    }

    $y = ($x[$a] -replace ('DC=', '') -replace (',', '.'))

    if ($y -eq $x[$a]) {
        Write-Host "  User provided domain/forest: $y"
    } else {
        Write-Host "  User provided domain/forest: $($x[$a]) -> $y"
    }

    if (($a -ne 0) -and ($x[$a] -ieq '*')) {
        Write-Host '    Skipping domain. Entry * is only allowed at first position in list.' -ForegroundColor Red
        continue
    }

    if ($y -match '[^a-zA-Z0-9.-]') {
        Write-Host '    Skipping domain. Allowed characters are a-z, A-Z, ., -.' -ForegroundColor Red
        continue
    }

    if (-not ($y.StartsWith('-'))) {
        if ($DomainsToCheckForGroups -icontains $y) {
            Write-Host '    Domain already in list.' -ForegroundColor Yellow
        } else {
            $DomainsToCheckForGroups += $y
        }
    } else {
        Write-Host '    Removing domain.'
        for ($z = 0; $z -lt $DomainsToCheckForGroups.Count; $z++) {
            if ($DomainsToCheckForGroups[$z] -ilike $y.substring(1)) {
                $DomainsToCheckForGroups[$z] = ''
            }
        }
    }
}


Write-Host 'Check for open LDAP port and connectivity'
CheckADConnectivity $DomainsToCheckForGroups 'LDAP' '  ' | Out-Null


Write-Host 'Check for open Global Catalog port and connectivity'
CheckADConnectivity $DomainsToCheckForGroups 'GC' '  ' | Out-Null


Write-Host 'Get AD properties of currently logged on user and his manager'
try {
    $ADPropsCurrentUser = ([adsisearcher]"(samaccountname=$env:username)").FindOne().Properties
} catch {
    $ADPropsCurrentUser = $null
    Write-Host '  Problem connecting to Active Directory, or user is a local user. Exiting.' -ForegroundColor Red
    exit 1
}

try {
    $ADPropsCurrentUserManager = ([adsisearcher]('(distinguishedname=' + $ADPropsCurrentUser.manager + ')')).FindOne().Properties
} catch {
    $ADPropsCurrentUserManager = $null
}


Write-Host 'Get Outlook signature file path(s)'
$SignaturePaths = @()
Get-ItemProperty 'hkcu:\software\microsoft\office\*\common\general' | Where-Object { $_.'Signatures' -ne '' } | ForEach-Object {
    Push-Location (Join-Path -Path $env:AppData -ChildPath 'Microsoft')
    $x = ('\\?\' + $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_.Signatures))
    if (Test-Path $x -IsValid) {
        if (-not (Test-Path $x -type container)) {
            New-Item -Path $x -ItemType directory -Force
        }
        $SignaturePaths += $x
        Write-Host "  $x"
    }
    Pop-Location
}


if ($AdditionalSignaturePath) {
    $AdditionalSignaturePath = ('\\?\' + $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($AdditionalSignaturePath))
    Write-Host "  Add additional signature path '$AdditionalSignaturePath'"
    if ((test-path $AdditionalSignaturePath -PathType Container) -eq $false) {
        New-Item -Path $AdditionalSignaturePath -ItemType Directory -Force
        if ((test-path $AdditionalSignaturePath -PathType Container) -eq $false) {
            write-host '    Path could not be accessed or created, ignoring path."
        } else {
            $SignaturePaths += $AdditionalSignaturePath
        }
    } else {
        $SignaturePaths += $AdditionalSignaturePath
    }
}


Write-Host 'Get mail addresses from Outlook profiles and corresponding registry paths'
$MailAddresses = @()
$RegistryPaths = @()
$LegacyExchangeDNs = @()

if ($OutlookDefaultProfile.length -eq '') {
    Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\*\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { (($_.'Account Name' -like '*@*.*') -and ($_.'Identity Eid' -ne '')) } | ForEach-Object {
        $MailAddresses += $_.'Account Name'
        $RegistryPaths += $_.PSPath
        $LegacyExchangeDN = ('/O=' + (((($_.'Identity Eid' | ForEach-Object { [char]$_ }) -join '' -replace [char]0) -split '/O=')[-1]).ToString().trim())
        if ($LegacyExchangeDN.length -le 3) {
            $LegacyExchangeDN = ''
        }
        $LegacyExchangeDNs += $LegacyExchangeDN
        Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
        Write-Host "    $($_.'Account Name')"
        if ($LegacyExchangeDN -eq '') {
            Write-Host '      No legacyExchangeDN found, assuming mailbox is no Exchange mailbox' -ForegroundColor Yellow
        } else {
            Write-Host '      Found legacyExchangeDN, assuming mailbox is an Exchange mailbox'
            Write-Host "        $LegacyExchangeDN"
        }
    }
} else {
    # current users mailbox in default profile
    Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\$OutlookDefaultProfile\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { $_.'Account Name' -ieq $ADPropsCurrentUser.mail } | ForEach-Object {
        $MailAddresses += $_.'Account Name'
        $RegistryPaths += $_.PSPath
        $LegacyExchangeDN = ('/O=' + (((($_.'Identity Eid' | ForEach-Object { [char]$_ }) -join '' -replace [char]0) -split '/O=')[-1]).ToString().trim())
        if ($LegacyExchangeDN.length -le 3) {
            $LegacyExchangeDN = ''
        }
        $LegacyExchangeDNs += $LegacyExchangeDN
        Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
        Write-Host "    $($_.'Account Name')"
        if ($LegacyExchangeDN -eq '') {
            Write-Host '      No legacyExchangeDN found, assuming mailbox is no Exchange mailbox' -ForegroundColor Yellow
        } else {
            Write-Host '      Found legacyExchangeDN, assuming mailbox is an Exchange mailbox'
            Write-Host "        $LegacyExchangeDN"
        }
    }

    # other mailboxes in default profile
    Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\$OutlookDefaultProfile\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { ($_.'Account Name' -like '*@*.*') -and ($_.'Account Name' -ine $ADPropsCurrentUser.mail) } | ForEach-Object {
        $MailAddresses += $_.'Account Name'
        $RegistryPaths += $_.PSPath
        $LegacyExchangeDN = ('/O=' + (((($_.'Identity Eid' | ForEach-Object { [char]$_ }) -join '' -replace [char]0) -split '/O=')[-1]).ToString().trim())
        if ($LegacyExchangeDN.length -le 3) {
            $LegacyExchangeDN = ''
        }
        $LegacyExchangeDNs += $LegacyExchangeDN
        Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
        Write-Host "    $($_.'Account Name')"
        if ($LegacyExchangeDN -eq '') {
            Write-Host '      No legacyExchangeDN found, assuming mailbox is no Exchange mailbox' -ForegroundColor Yellow
        } else {
            Write-Host '      Found legacyExchangeDN, assuming mailbox is an Exchange mailbox'
            Write-Host "        $LegacyExchangeDN"
        }
    }

    # all other mailboxes in all other profiles
    Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\*\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { $_.'Account Name' -like '*@*.*' } | ForEach-Object {
        if ($RegistryPaths -notcontains $_.PSPath) {
            $MailAddresses += $_.'Account Name'
            $RegistryPaths += $_.PSPath
            $LegacyExchangeDN = ('/O=' + (((($_.'Identity Eid' | ForEach-Object { [char]$_ }) -join '' -replace [char]0) -split '/O=')[-1]).ToString().trim())
            if ($LegacyExchangeDN.length -le 3) {
                $LegacyExchangeDN = ''
            }
            $LegacyExchangeDNs += $LegacyExchangeDN
            Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
            Write-Host "    $($_.'Account Name')"
            if ($LegacyExchangeDN -eq '') {
                Write-Host '      No legacyExchangeDN found, assuming mailbox is no Exchange mailbox' -ForegroundColor Yellow
            } else {
                Write-Host '      Found legacyExchangeDN, assuming mailbox is an Exchange mailbox'
                Write-Host "        $LegacyExchangeDN"
            }
        }
    }
}


Write-Host 'Get all signature files and categorize them'
$SignatureFilesCommon = @{}
$SignatureFilesGroup = @{}
$SignatureFilesGroupFilePart = @{}
$SignatureFilesMailbox = @{}
$SignatureFilesMailboxFilePart = @{}
$SignatureFilesDefaultNew = @{}
$SignatureFilesDefaultReplyFwd = @{}
$global:SignatureFilesDone = @()
$SignatureFilesGroupSIDs = @{}

foreach ($SignatureFile in ((Get-ChildItem -LiteralPath $SignatureTemplatePath -File -Filter '*.docx') | Sort-Object)) {
    Write-Host ("  '$($SignatureFile.Name)'")
    $x = $SignatureFile.name -split '\.(?![\w\s\d]*\[*(\]|@))'
    if ($x.count -ge 3) {
        $SignatureFilePart = $x[-2]
        $SignatureFileTargetName = ($x[($x.count * -1)..-3] -join '.') + '.' + $x[-1]
    } else {
        $SignatureFilePart = ''
        $SignatureFileTargetName = $SignatureFile.Name
    }

    $SignatureFileTimeActive = $true
    if ($SignatureFilePart -match '\[\d{12}-\d{12}\]') {
        $SignatureFileTimeActive = $false
        Write-Host '    Time based signature'
        foreach ($SignatureFilePartTag in ([regex]::Matches((($SignatureFilePart -replace '(?i)\[DefaultNew\]', '') -replace '(?i)\[DefaultReplyFwd\]', ''), '\[\d{12}-\d{12}\]').captures.value)) {
            foreach ($DateTimeTag in ([regex]::Matches($SignatureFilePartTag, '\[\d{12}-\d{12}\]').captures.value)) {
                Write-Host "      $($DateTimeTag): " -NoNewline
                try {
                    $DateTimeTagStart = [System.DateTime]::ParseExact(($DateTimeTag.tostring().Substring(1, 12)), 'yyyyMMddHHmm', $null)
                    $DateTimeTagEnd = [System.DateTime]::ParseExact(($DateTimeTag.tostring().Substring(14, 12)), 'yyyyMMddHHmm', $null)

                    if (((Get-Date) -ge $DateTimeTagStart) -and ((Get-Date) -le $DateTimeTagEnd)) {
                        Write-Host 'Current DateTime in range'
                        $SignatureFileTimeActive = $true
                    } else {
                        Write-Host 'Current DateTime out of range'
                    }
                } catch {
                    Write-Host 'Invalid DateTime, ignoring tag' -ForegroundColor Red
                }
            }
        }
        if ($SignatureFileTimeActive -eq $true) {
            Write-Host '      Current DateTime is in range of at least one DateTime tag, using signature'
        } else {
            Write-Host '      Current DateTime is not in range of any DateTime tag, ignoring signature' -ForegroundColor Yellow
        }
    }

    if ($SignatureFileTimeActive -ne $true) {
        continue
    }

    [regex]::Matches((($SignatureFilePart -replace '(?i)\[DefaultNew\]', '') -replace '(?i)\[DefaultReplyFwd\]', ''), '\[(.*?)\]').captures.value | ForEach-Object {
        $SignatureFilePartTag = $_
        if ($SignatureFilePartTag -match '\[(.*?)@(.*?)\.(.*?)\]') {
            Write-Host '    Mailbox specific signature'
            $SignatureFilesMailbox.add($SignatureFile.FullName, $SignatureFileTargetName)
            $SignatureFilesMailboxFilePart.add($SignatureFile.FullName, $SignatureFilePart)
        } elseif ($SignatureFilePartTag -match '\[.*? .*?\]') {
            Write-Host '    Group specific signature'
            (([regex]'\[.*? .*?\]').Matches($SignatureFilePart)).value | ForEach-Object {
                $groupname = $_
                $NTName = ((($_ -replace '\[', '') -replace '\]', '') -replace '(.*?) (.*)', '$1\$2')
                if (-not $SignatureFilesGroupSIDs.ContainsKey($_)) {
                    try {
                        $SignatureFilesGroupSIDs.add($_, (New-Object System.Security.Principal.NTAccount($NTName)).Translate([System.Security.Principal.SecurityIdentifier]))
                    } catch {
                        # No group with this sAMAccountName found. Maybe it's a display name?
                        try {
                            $objTrans = New-Object -ComObject 'NameTranslate'
                            $objNT = $objTrans.GetType()
                            $objNT.InvokeMember('Init', 'InvokeMethod', $Null, $objTrans, (1, ($NTName -split '\\')[0])) # 1 = ADS_NAME_INITTYPE_DOMAIN
                            $objNT.InvokeMember('Set', 'InvokeMethod', $Null, $objTrans, (4, ($NTName -split '\\')[1]))
                            $SignatureFilesGroupSIDs.add($groupname, ((New-Object System.Security.Principal.NTAccount(($objNT.InvokeMember('Get', 'InvokeMethod', $Null, $objTrans, 3)))).Translate([System.Security.Principal.SecurityIdentifier])).value)
                        } catch {
                        }
                    }
                }
            }
            foreach ($key in $SignatureFilesGroupSIDs.keys) {
                $SignatureFilePart = $SignatureFilePart.replace($key, ($key + ('[' + $SignatureFilesGroupSIDs[$key] + ']')))
            }
            $SignatureFilesGroup.add($SignatureFile.FullName, $SignatureFileTargetName)
            $SignatureFilesGroupFilePart.add($SignatureFile.FullName, $SignatureFilePart)
        } else {
            Write-Host '    Common signature'
            $SignatureFilesCommon.add($SignatureFile.FullName, $SignatureFileTargetName)
        }
    }

    if ($SignatureFilePart -match '(?i)\[DefaultNew\]') {
        $SignatureFilesDefaultNew.add($SignatureFile.FullName, $SignatureFileTargetName)
        Write-Host '    Default signature for new mails'
    }

    if ($SignatureFilePart -match '(?i)\[DefaultReplyFwd\]') {
        $SignatureFilesDefaultReplyFwd.add($SignatureFile.FullName, $SignatureFileTargetName)
        Write-Host '    Default signature for replies and forwards'
    }
}


Write-Host 'Signature group name to SID mapping'
foreach ($key in $SignatureFilesGroupSIDs.keys) {
    Write-Host "  $($key) = $($SignatureFilesGroupSIDs[$key])"
}


# Start Word, as we need it to edit signatures
try {
    $COMWord = New-Object -ComObject word.application
} catch {
    Write-Host 'Word not installed or not working correctly. Exiting.' -ForegroundColor Red
    exit 1
}


# Process each mail address only once, but each corresponding registry path
for ($AccountNumberRunning = 0; $AccountNumberRunning -lt $MailAddresses.count; $AccountNumberRunning++) {
    if ($AccountNumberRunning -le $MailAddresses.IndexOf($MailAddresses[$AccountNumberRunning])) {
        Write-Host "Mailbox $($MailAddresses[$AccountNumberRunning])"
        Write-Host "  $($LegacyExchangeDNs[$AccountNumberRunning])"

        $UserDomain = ''

        Write-Host '  Get AD properties and group membership of mailbox'
        $GroupsSIDs = @()

        if (($($LegacyExchangeDNs[$AccountNumberRunning]) -ne '')) {
            # Loop through domains until the first one knows the legacyExchangeDN
            for ($DomainNumber = 0; (($DomainNumber -lt $DomainsToCheckForGroups.count) -and ($UserDomain -eq '')); $DomainNumber++) {
                if (($DomainsToCheckForGroups[$DomainNumber] -ne '')) {
                    Write-Host "    $($DomainsToCheckForGroups[$DomainNumber]) (searching for mailbox user object and its group membership)"
                    $Search.searchroot = New-Object System.DirectoryServices.DirectoryEntry("GC://$($DomainsToCheckForGroups[$DomainNumber])")
                    $Search.filter = "(&(objectclass=user)(legacyExchangeDN=$($LegacyExchangeDNs[$AccountNumberRunning])))"
                    $u = $Search.FindOne()
                    if (($u.path -ne '') -and ($null -ne $u.path)) {
                        # Connect to Domain Controller (LDAP), as Global Catalog (GC) does not have all attributes,
                        # for example tokenGroups including domain local groups
                        $UserAccount = [ADSI]"LDAP://$($u.properties.distinguishedname)"
                        $ADPropsCurrentMailbox = $UserAccount.Properties
                        try {
                            $Search.filter = "(distinguishedname=$($ADPropsCurrentMailbox.Manager))"
                            $ADPropsCurrentMailboxManager = ([ADSI]"$(($Search.FindOne()).path)").Properties
                        } catch {
                        }
                        $UserDomain = $DomainsToCheckForGroups[$DomainNumber]
                        $SIDsToCheckInTrusts = @()
                        $SIDsToCheckInTrusts += $UserAccount.objectSid
                        $UserAccount.GetInfoEx(@('tokengroups'), 0)

                        foreach ($sidBytes in $UserAccount.Properties.tokenGroups) {
                            $sid = New-Object System.Security.Principal.SecurityIdentifier($sidbytes, 0)
                            $GroupsSIDs += $sid.tostring()
                            Write-Host "      $sid"
                        }
                        $UserAccount.GetInfoEx(@('tokengroupsglobalanduniversal'), 0)
                        $SIDsToCheckInTrusts += $UserAccount.properties.tokengroupsglobalanduniversal
                    }
                }
            }

            # Loop through all domains to check if the mailbox account has a group membership there
            # Across a trust, a user can only be added to a domain local group.
            # Domain local groups can not be used outside their own domain, so we don't need to query recursively
            if ($SIDsToCheckInTrusts.count -gt 0) {
                $LdapFilterSIDs = '(|'
                $SIDsToCheckInTrusts | ForEach-Object {
                    try {
                        $SidHex = @()
                        $ot = New-Object System.Security.Principal.SecurityIdentifier($_, 0)
                        $c = New-Object 'byte[]' $ot.BinaryLength
                        $ot.GetBinaryForm($c, 0)
                        $c | ForEach-Object {
                            $SidHex += $('\{0:x2}' -f $_)
                        }
                        $LdapFilterSIDs += ('(objectsid=' + $($SidHex -join '') + ')')
                    } catch {
                    }
                }
                $LdapFilterSIDs += ')'
            } else {
                $LdapFilterSIDs = ''
            }

            for ($DomainNumber = 0; $DomainNumber -lt $DomainsToCheckForGroups.count; $DomainNumber++) {
                if (($DomainsToCheckForGroups[$DomainNumber] -ne '') -and ($DomainsToCheckForGroups[$DomainNumber] -ine $UserDomain) -and ($UserDomain -ne '')) {
                    Write-Host "    $($DomainsToCheckForGroups[$DomainNumber]) (mailbox group membership across trusts, takes some time)"
                    $Search.searchroot = New-Object System.DirectoryServices.DirectoryEntry("GC://$($DomainsToCheckForGroups[$DomainNumber])")
                    $Search.filter = "(&(objectclass=foreignsecurityprincipal)$LdapFilterSIDs)"
                    foreach ($fsp in $Search.FindAll()) {
                        if (($fsp.path -ne '') -and ($null -ne $fsp.path)) {
                            if ((CheckADConnectivity $(($fsp.path -split ',DC=')[1..999] -join '.') 'GC' '      ') -eq $true) {
                                # Foreign Security Principals do not have the tokenGroups attribute
                                # We need to switch to another, slower search method
                                # member:1.2.840.113556.1.4.1941:= (LDAP_MATCHING_RULE_IN_CHAIN) returns groups containing a specific DN as member
                                # A Foreign Security Principal ist created in each (sub)domain, in which it is granted permissions,
                                # and it can only be member of a domain local group - so we set the searchroot to the (sub)domain of the Foreign Security Principal.
                                $Search.searchroot = New-Object System.DirectoryServices.DirectoryEntry("GC://$((($fsp.path -split ',DC=')[1..999] -join '.'))")
                                $Search.filter = "(&(groupType:1.2.840.113556.1.4.803:=4)(member:1.2.840.113556.1.4.1941:=$($fsp.Properties.distinguishedname)))"

                                foreach ($group in $Search.findall()) {
                                    $sid = New-Object System.Security.Principal.SecurityIdentifier($group.properties.objectsid[0], 0)
                                    $GroupsSIDs += $sid.tostring()
                                    Write-Host "        $sid"
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Write-Host '    Skipping, as mailbox has no legacyExchangeDN and is assumed not to be an Exchange mailbox' -ForegroundColor yellow
        }


        Write-Host '  Get SMTP addresses'
        $CurrentMailboxSMTPAddresses = @()
        if (($($LegacyExchangeDNs[$AccountNumberRunning]) -ne '')) {
            $ADPropsCurrentMailbox.proxyaddresses | ForEach-Object {
                if ([string]$_ -ilike 'smtp:*') {
                    $CurrentMailboxSMTPAddresses += [string]$_ -ireplace 'smtp:', ''
                    Write-Host ('    ' + ([string]$_ -ireplace 'smtp:', ''))
                }
            }
        } else {
            $CurrentMailboxSMTPAddresses += $($MailAddresses[$AccountNumberRunning])
            Write-Host '    Skipping, as mailbox has no legacyExchangeDN and is assumed not to be an Exchange mailbox' -ForegroundColor Yellow
            Write-Host '    Using mailbox name as single known SMTP address' -ForegroundColor Yellow
        }

        Write-Host '  Get data for replacement variables'
        $ReplaceHash = @{}
        if (Test-Path -Path $ReplacementVariableConfigFile -PathType Leaf) {
            (Get-Content -LiteralPath $ReplacementVariableConfigFile) | ForEach-Object {
                if ($_.tostring().StartsWith('$ReplaceHash[''$CURRENT')) {
                    try {
                        Invoke-Expression -Command $_
                    } catch {
                        Write-Host "    Error: $_" -ForegroundColor Red
                    }
                } elseif (!($_.tostring().StartsWith('#')) -and ($_.tostring() -ne '')) {
                    Write-Host "        Invalid line: $_" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "    Problem connecting to or reading from file '$ReplacementVariableConfigFile'. " -ForegroundColor Yellow
        }
        foreach ($replaceKey in ($replaceHash.Keys | Sort-Object)) {
            if ($replaceKey -notin ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$', '$CURRENTMAILBOXMANAGERPHOTODELETEEMPTY$', '$CURRENTMAILBOXPHOTODELETEEMPTY$', '$CURRENTUSERMANAGERPHOTODELETEEMPTY$', '$CURRENTUSERPHOTODELETEEMPTY$')) {
                Write-Host "    $($replaceKey): $($replaceHash[$replaceKey])"
            } else {
                Write-Host "    $($replaceKey): " -NoNewline
                if ($null -ne $($replaceHash[$replaceKey])) {
                    Write-Host 'Photo available'
                } else {
                    Write-Host 'No photo available'
                }
            }
        }

        # Export pictures if available
        ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$') | ForEach-Object {
            if ($null -ne $ReplaceHash[$_]) {
                $ReplaceHash[$_] | Set-Content -LiteralPath (Join-Path -Path $env:temp -ChildPath ($_ + '.jpeg')) -Encoding Byte -Force
            }
        }

        Write-Host '  Process common signatures'
        foreach ($Signature in ($SignatureFilesCommon.GetEnumerator() | Sort-Object)) {
            Set-Signatures
        }

        Write-Host '  Process group signatures'
        $SignatureHash = @{}
        if (($($LegacyExchangeDNs[$AccountNumberRunning]) -ne '')) {
            foreach ($x in $SignatureFilesGroupFilePart.GetEnumerator()) {
                $GroupsSIDs | ForEach-Object {
                    if ($x.Value.tolower().Contains('[' + $_.tolower() + ']')) {
                        $SignatureHash.add($x.Name, $SignatureFilesGroup[$x.Name])
                    }
                }
            }
            foreach ($Signature in ($SignatureHash.GetEnumerator() | Sort-Object)) {
                Set-Signatures
            }
        } else {
            $CurrentMailboxSMTPAddresses += $($MailAddresses[$AccountNumberRunning])
            Write-Host '    Skipping, as mailbox has no legacyExchangeDN and is assumed not to be an Exchange mailbox' -ForegroundColor Yellow
        }

        Write-Host '  Process mail address specific signatures'
        $SignatureHash = @{}
        foreach ($x in $SignatureFilesMailboxFilePart.GetEnumerator()) {
            foreach ($y in $CurrentMailboxSMTPAddresses) {
                if ($x.Value.tolower().contains('[' + $y.tolower() + ']')) {
                    $SignatureHash.add($x.Name, $SignatureFilesMailbox[$x.Name])
                }
            }
        }
        foreach ($Signature in ($SignatureHash.GetEnumerator() | Sort-Object)) {
            Set-Signatures
        }

        # Delete photos from file system
        ('$CURRENTMAILBOXMANAGERPHOTO$', '$CURRENTMAILBOXPHOTO$', '$CURRENTUSERMANAGERPHOTO$', '$CURRENTUSERPHOTO$') | ForEach-Object {
            Remove-Item -LiteralPath (Join-Path -Path $env:temp -ChildPath ($_ + '.jpeg')) -Force -ErrorAction SilentlyContinue
            $ReplaceHash.Remove($_)
            $ReplaceHash.Remove(($_[-999..-2] -join '') + 'DELETEEMPTY$')
        }
    }

    # Outlook Web Access
    if (($SetCurrentUserOutlookWebSignature -eq $true) -and ($ADPropsCurrentMailbox.mail -ieq $ADPropsCurrentUser.mail)) {
        Write-Host '  Set Outlook Web signature'
        # if the mailbox of the currenlty logged on user is part of his default Outlook Profile, copy the signature to OWA
        for ($j = 0; $j -lt $MailAddresses.count; $j++) {
            if ($MailAddresses[$j] -ieq [string]$ADPropsCurrentUser.mail) {
                if ($RegistryPaths[$j] -like ('*\Outlook\Profiles\' + $OutlookDefaultProfile + '\9375CFF0413111d3B88A00104B2A6676\*')) {
                    try {
                        $TempNewSig = Get-ItemPropertyValue -LiteralPath $RegistryPaths[$j] -Name 'New Signature'
                    } catch {
                        $TempNewSig = ''
                    }
                    try {
                        $TempReplySig = Get-ItemPropertyValue -LiteralPath $RegistryPaths[$j] -Name 'Reply-Forward Signature'
                    } catch {
                        $TempReplySig = ''
                    }
                    if (($TempNewSig -eq '') -and ($TempReplySig -eq '')) {
                        Write-Host '    No default signatures defined, nothing to do'
                        $TempOWASigFile = $null
                        $TempOWASigSetNew = $null
                        $TempOWASigSetReply = $null
                    }

                    if (($TempNewSig -ne '') -and ($TempReplySig -eq '')) {
                        Write-Host '    Signature for new mails found'
                        $TempOWASigFile = $TempNewSig
                        $TempOWASigSetNew = 'True'
                        $TempOWASigSetReply = 'False'
                    }

                    if (($TempNewSig -eq '') -and ($TempReplySig -ne '')) {
                        Write-Host '    Default signature for reply/forward found'
                        $TempOWASigFile = $TempReplySig
                        $TempOWASigSetNew = 'False'
                        $TempOWASigSetReply = 'True'
                    }


                    if ((($TempNewSig -ne '') -and ($TempReplySig -ne '')) -and ($TempNewSig -ine $TempReplySig)) {
                        Write-Host '    Different default signatures for new and reply/forward found, using new signature'
                        $TempOWASigFile = $TempNewSig
                        $TempOWASigSetNew = 'True'
                        $TempOWASigSetReply = 'False'
                    }

                    if ((($TempNewSig -ne '') -and ($TempReplySig -ne '')) -and ($TempNewSig -ieq $TempReplySig)) {
                        Write-Host '    Same default signature for new and reply/forward'
                        $TempOWASigFile = $TempNewSig
                        $TempOWASigSetNew = 'True'
                        $TempOWASigSetReply = 'True'
                    }
                    if (($null -ne $TempOWASigFile) -and ($TempOWASigFile -ne '')) {
                        try {
                            $hsHtmlSignature = (Get-Content -LiteralPath ('\\?\' + (Join-Path -Path ($SignaturePaths[0] -replace [regex]::escape('\\?\')) -ChildPath ($TempOWASigFile + '.htm'))) -Raw).ToString()
                            $stTextSig = (Get-Content -LiteralPath ('\\?\' + (Join-Path -Path ($SignaturePaths[0] -replace [regex]::escape('\\?\')) -ChildPath ($TempOWASigFile + '.txt'))) -Raw).ToString()

                            $OutlookWebHash = @{}
                            # Keys are case sensitive when setting them
                            $OutlookWebHash.Add('signaturehtml', $hsHtmlSignature)
                            $OutlookWebHash.Add('signaturetext', $stTextSig)
                            $OutlookWebHash.Add('signaturetextonmobile', $stTextSig)
                            $OutlookWebHash.Add('autoaddsignature', $TempOWASigSetNew)
                            $OutlookWebHash.Add('autoaddsignatureonmobile', $TempOWASigSetNew)
                            $OutlookWebHash.Add('autoaddsignatureonreply', $TempOWASigSetReply)

                            try {
                                Copy-Item -Path '.\bin\Microsoft.Exchange.WebServices.dll' -Destination (Join-Path -Path $env:temp -ChildPath 'Microsoft.Exchange.WebServices.dll') -Force
                            } catch {
                            }

                            Import-Module -Name (Join-Path -Path $env:temp -ChildPath 'Microsoft.Exchange.WebServices.dll') -Force
                            $exchService = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService
                            $exchService.UseDefaultCredentials = $true
                            $exchService.AutodiscoverUrl($ADPropsCurrentUser.mail)
                            $folderid = New-Object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Root, $($ADPropsCurrentUser.mail))
                            #Specify the Root folder where the FAI Item is
                            $UsrConfig = [Microsoft.Exchange.WebServices.Data.UserConfiguration]::Bind($exchService, 'OWA.UserOptions', $folderid, [Microsoft.Exchange.WebServices.Data.UserConfigurationProperties]::All)

                            foreach ($OutlookWebHashKey in $OutlookWebHash.Keys) {
                                if ($UsrConfig.Dictionary.ContainsKey($OutlookWebHashKey)) {
                                    $UsrConfig.Dictionary[$OutlookWebHashKey] = $OutlookWebHash.$OutlookWebHashKey
                                } else {
                                    $UsrConfig.Dictionary.Add($OutlookWebHashKey, $OutlookWebHash.$OutlookWebHashKey)
                                }
                            }

                            $UsrConfig.Update()
                        } catch {
                            Write-Host '    Error setting Outlook Web signature, please contact your administrator' -ForegroundColor Red
                        }

                        Remove-Module -Name Microsoft.Exchange.WebServices -Force
                        Remove-Item (Join-Path -Path $env:temp -ChildPath 'Microsoft.Exchange.WebServices.dll') -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}


# Quit word, as all signatures have been edited
$COMWord.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($COMWord) | Out-Null
Remove-Variable COMWord


# Delete old signatures created by this script, which are no longer available in $SignatureTemplatePath
# We check all local signatures for a specific marker in HTML code, so we don't touch user created signatures
Write-Host 'Remove old signatures created by this script, which are no longer centrally available'
$SignaturePaths | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Filter '*.htm' -File | ForEach-Object {
        if ((Get-Content -LiteralPath $_.fullname -Raw) -like ('*' + $HTMLMarkerTag + '*')) {
            if (($_.name -notin $global:SignatureFilesDone) -and ($_.name -notin $SignatureFilesCommon.values) -and ($_.name -notin $SignatureFilesMailbox.Values) -and ($_.name -notin $SignatureFilesGroup.Values)) {
                Write-Host ("  '" + $([System.IO.Path]::ChangeExtension($_.fullname, '')) + "*'")
                Remove-Item -LiteralPath $_.fullname -Force -ErrorAction silentlycontinue
                Remove-Item -LiteralPath ($([System.IO.Path]::ChangeExtension($_.fullname, '.rtf'))) -Force -ErrorAction silentlycontinue
                Remove-Item -LiteralPath ($([System.IO.Path]::ChangeExtension($_.fullname, '.txt'))) -Force -ErrorAction silentlycontinue
            }
        }
    }
}


# Delete user created signatures if the corresponding parameter is set
if ($DeleteUserCreatedSignatures -eq $true) {
    Write-Host 'Remove user created signatures'
    $SignaturePaths | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Filter '*.htm' -File | ForEach-Object {
            if ((Get-Content -LiteralPath $_.fullname -Raw) -notlike ('*' + $HTMLMarkerTag + '*')) {
                    Write-Host ("  '" + $([System.IO.Path]::ChangeExtension($_.fullname, '')) + "*'")
                    Remove-Item -LiteralPath $_.fullname -Force -ErrorAction silentlycontinue
                    Remove-Item -LiteralPath ($([System.IO.Path]::ChangeExtension($_.fullname, '.rtf'))) -Force -ErrorAction silentlycontinue
                    Remove-Item -LiteralPath ($([System.IO.Path]::ChangeExtension($_.fullname, '.txt'))) -Force -ErrorAction silentlycontinue
            }
        }
    }
}


Write-Host 'Script ended'
