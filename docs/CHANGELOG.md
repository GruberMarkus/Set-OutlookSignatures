<!-- omit in toc -->
# <a href="https://github.com/GruberMarkus/Set-OutlookSignatures" target="_blank"><img src="../src/logo/Set-OutlookSignatures%20Logo.png" width="400" title="Set-OutlookSignatures" alt="Set-OutlookSignatures"></a><br>Centrally manage and deploy Outlook text signatures and Out of Office auto reply messages.<br><a href="https://github.com/GruberMarkus/Set-OutlookSignatures/blob/main/docs/LICENSE.txt" target="_blank"><img src="https://img.shields.io/github/license/GruberMarkus/Set-OutlookSignatures" alt=""></a> <a href="https://www.paypal.com/donate/?business=JBM584K3L5PX4&item_name=Set-OutlookSignatures&no_recurring=0&currency_code=EUR" target="_blank"><img src="https://img.shields.io/badge/sponsor-grey?logo=paypal" alt=""></a> <img src="https://raw.githubusercontent.com/GruberMarkus/my-traffic2badge/traffic/traffic-Set-OutlookSignatures/views.svg" alt="" data-external="1"> <img src="https://raw.githubusercontent.com/GruberMarkus/my-traffic2badge/traffic/traffic-Set-OutlookSignatures/clones.svg" alt="" data-external="1"> <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/network/members" target="_blank"><img src="https://img.shields.io/github/forks/GruberMarkus/Set-OutlookSignatures" alt="" data-external="1"></a> <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases" target="_blank"><img src="https://img.shields.io/github/downloads/GruberMarkus/Set-OutlookSignatures/total" alt="" data-external="1"></a> <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/stargazers" target="_blank"><img src="https://img.shields.io/github/stars/GruberMarkus/Set-OutlookSignatures" alt="" data-external="1"></a> <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/issues" target="_blank"><img src="https://img.shields.io/github/issues/GruberMarkus/Set-OutlookSignatures" alt="" data-external="1"></a>  

# Changelog

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.3.1" target="_blank">v2.3.1</a> - 2021-11-05
### Fixed
- Ignore mail-enabled users an mailbox search to avoid binding to the wrong Exchange object in migration scenarios (which would lead to wrong replacement variable data and group membership)
- When connecting to Exchange Online, check for valid mailbox in addition to valid credentials
- Clarify port requirements and group membership evaluation in documentation

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.3.0" target="_blank">v2.3.0</a> - 2021-10-08
### Added
- Support for mailboxes in Microsoft 365, including hybrid and cloud only scenarios (see '.\docs\README.html' and '.\config\default graph config.ps1' for details)
- Possibility to use ini files instead of file name tags, including settings for template sort order, sort culture, and custom Outlook signature names (see parameters 'SignatureIniPath' and 'OOFIniPath' for details)
- New default replacement variables '\$CURRENT\[...\]OFFICE\$' and '\$CURRENT\[...\]COMPANY\$', including updated templates
- Enterprise ready workaround for Word security warning when converting documents with linked images
- FAQ: The script hangs at HTM/RTF export, Word shows a security warning!?
- FAQ: Isn't a plural noun in the script name against PowerShell best practices?
- FAQ: How to avoid empty lines when replacement variables return an empty string?
- FAQ: Is there a roadmap for future versions?
- Code of Conduct (see '.\docs\CODE_OF_CONDUCT.html' for details)
### Fixed
- User could connect to hidden Word instance used for conversion of DOCX templates
- Do no classify templates with unknown tags as common templates 
- Word settings temporarily changed by the script are now also restored to their original values when the script ends due to an unexpected error
- Do not try to change read-only Word attributes \<image>.hyperlink.name and \<image>.hyperlink.addressold (regression bug)
### Changed
- The parameter DomainsToCheckForGroups is also available under the more descriptive name TrustsToCheckForGroups. Both names can be used, functionality is unchanged.
- Contribution opportunities in '.\docs\CONTRIBUTING.html'

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.2.1" target="_blank">v2.2.1</a> - 2021-09-15
### Fixed
- Allow multi-relative paths (Example: 'c:\a\b\x\\..\c\y\z\\..\\..\d' -> 'c:\a\b\c\d')

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.2.0" target="_blank">v2.2.0</a> - 2021-09-15
### Changed
- Make script compatible with PowerShell Core 7.x on Windows (Linux and MacOS are not supported yet)
- Reduce and speed up Active Directory queries by only accepting input in the 'Domain\User' or UPN (User Principal Name) format for the 'SimulateUser' parameter
- Reduce and speed up Active Directory queries by only accepting e-mail addresses as input for the 'SimulateMailboxes' parameter
- Revise repository structure, as well as the process for development, build and release
### Added
- Full support for Exchange mailboxes added in Outlook as POP3 or IMAP4 accounts
- Add FAQs: "Where can I find the changelog?", "How can I contribute, propose a new feature or file a bug?", "What is the recommended approach for custom configuration files?"
- Add file hash of build artifacts to release information and hashes.txt 
- Add dark mode support and badges to documentation files
### Fixed
- Do not show an error message when no default Outlook profile is configured
- Avoid additional blank lines at the end of TXT signature files when DOCX templates are used (<a href="https://github.com/GruberMarkus/Set-OutlookSignatures/issues/13" target="_blank">#13</a>)
- Detect user's domain correctly when user and computer belong to different AD forests
- Do not show an error message when only external or interal OOF message is set
- Set current user's OWA signature even when mailbox is in another Outlook profile than the default one

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.1.2" target="_blank">v2.1.2</a> - 2021-09-03
### Fixed
- Correct extension attributes being shown as empty in replacement variables (<a href="https://github.com/GruberMarkus/Set-OutlookSignatures/issues/11" target="_blank">#11</a>) (<a href="https://github.com/goranko73" target="_blank">@goranko73</a>)

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.1.1" target="_blank">v2.1.1</a> - 2021-08-26
### Changed
- Disable positional binding of passed arguments for easier debugging.
- Rename '\bin\licenses.txt' to '\bin\LICENSE.txt'
### Added
- "implementation approach.html" describes the recommended approach for implementing the software, based on real-life experience implementing the script in a multi-client environment with a five-digit number of mailboxes.
- New FAQ "How to create a shortcut to the script with parameters?"
- New FAQ "What is the recommended approach for implementing the software?"
- Add multi-client capability hint to script description and readme file

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.1.0" target="_blank">v2.1.0</a> - 2021-08-13
### Changed
- Enhance long file path handling
- Enhance FullLanguage mode detection
### Added
- FAQ: How do I start the script from the command line or a scheduled task?
- Added command line and task scheduler example to script
- Logo and icon files are now part of the download package

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.0.2" target="_blank">v2.0.2</a> - 2021-07-23
### Changed
- Inform the user when an Active Directory search returns less or more than one result
- Readme chapter "Simulation mode" updated
### Added
- Readme FAQ "Can multiple script instances run in parallel?"
### Fixed
- Readme link about MS Word ExportPictureWithMetafile registry key to avoid huge RTF files supplemented by alternate link to Internet Archive Wayback Machine (<a href="https://github.com/GruberMarkus/Set-OutlookSignatures/issues/9" target="_blank">#9</a>) (<a href="https://github.com/nitishkanu820" target="_blank">@nitishkanu820</a>)

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.0.1" target="_blank">v2.0.1</a> - 2021-07-22
_Do not use this release. It was withdrawn due to a severe problem._

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v2.0.0" target="_blank">v2.0.0</a> - 2021-07-21
### Changed
- **Breaking:** The configuration file is no longer a plain text file, but a full PowerShell script. This allows for complex replacement variable handling (complex string transformations, retrieving information from web services and databases, etc.).
- When enumerating and categoring templates, category defining information is logged (assigned mail address, group name including SID)
- Advanced primary mailbox detection and sorting
- Easier readable output (s cript start and end times are shown, logical grouping of tasks (Outlook tasks first, basic AD tasks second, template enumeration third, then signature handling tasks), vertical whitespace between main tasks makes output easier consumable visually)
### Added
- Simulation mode
- Major script steps now show a timestamp
- Readme for "Simulation mode" and FAQ "How can I log the script output?"
### Fixed
- Templates with multiple groups or multiple mail addresses were not applied correctly and led to redundant Active Directory queries

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.6.1" target="_blank">v1.6.1</a> - 2021-06-30
### Fixed
- Empty AdditionalSignaturePath leads to error (<a href="https://github.com/GruberMarkus/Set-OutlookSignatures/issues/8" target="_blank">#8</a>)

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.6.0" target="_blank">v1.6.0</a> - 2021-06-26
### Changed
- Change template path structure
- Update readme
- Update templates
### Added
- Add support for HTML template files (.htm)
- Add parameter UseHtmlTemplates to switch from DOCX to HTML template handling
- Consider images in .docx templates with different text wrapping setting (Shapes for "in line with text" and InlineShapes for all other text wrapping settings)
### Fixed
- Check existence of signature file before trying to set Outlook web signature

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.5.4" target="_blank">v1.5.4</a> - 2021-06-24
### Added
- New FAQ: Why DOCX as template format and not HTML? Signatures in Outlook sometimes look different than my DOCX templates.
### Fixed
- Fix: Consider images with different text wrapping setting (Shapes for "in line with text" and InlineShapes for all other text wrapping settings).

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.5.3" target="_blank">v1.5.3</a> - 2021-06-23
### Fixed
- Fix problem connecting to WebDAV-paths.
- Fix readme file to reflect enhanced WebDAV possibilities in path parameters.

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.5.2" target="_blank">v1.5.2</a> - 2021-06-21
### Fixed
- Fix handling of Outlook Web connection error.
- Fix readme: OOF templates are not applied when currently active or scheduled.

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.5.1" target="_blank">v1.5.1</a> - 2021-06-20
## Fixed
- Provide readme.html in releases, not markdown file
- Update link formatting in readme files
- Add attribution for logo source
- Update logo path and dependencies

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.5.0" target="_blank">v1.5.0</a> - 2021-06-18
### Added
- Add support for Out of Office (OOF) auto reply messages
- New parameter SetCurrentUserOOFMessage
- New parameter OOFTemplatePath
- Add sample files for OOF templates '.\OOF templates'

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.4.0" target="_blank">v1.4.0</a> - 2021-06-17
### Added
- New parameter AdditionalSignaturePath

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.3.0" target="_blank">v1.3.0</a> - 2021-06-16
### Added
- New parameter DeleteUserCreatedSignatures
- New parameter SetCurrentUserOutlookWebSignature

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.2.1" target="_blank">v1.2.1</a>  2021-06-14
### Fixed
- Fix signature group name to SID mapping
- Make logo work with every background (transparency, white glow)

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.2.0" target="_blank">v1.2.0</a> - 2021-06-11
## Changed
- Reduce LDAP queries by getting replacement variable data per mailbox, not per signature file and mailbox
- Speed up variable replacement in image metadata
## Added
- Show replacement variable values in output
- Show variables and script root in output
- Show warning when replacement variable config file can not be accessed
- Update signature template file 'Test all signature replacement variables.docx'
- Include info about case sensitivity in file 'default replacement variables.txt'

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.1.0" target="_blank">v1.1.0</a> - 2021-06-10
### Changed
-Move all replacement variable definitions to './config/default replacement variables.txt'
-Update README: Add logo, modify chapter ordering, document parameter ReplacementVariableConfigFile
### Added
- Add Exchange Extension variables 1..15 to './config/default replacement variables.txt' and 'Test all signature replacement variables.docx'
- Create subdirectories for binaries and configurations, adapt script to work with new subdirectories
- Add a logo
- Adapt script to include script information (version and others) in code and output
### Fixed
- Modify license.txt to that GitHub recognizes the license type
- Add '.gitattributes' file to ignore '.git*' folders and README in relase
- Add 'readme.txt', a plain text version of README, which can be read on all systems with on-board tools.

## <a href="https://github.com/GruberMarkus/Set-OutlookSignatures/releases/tag/v1.0.0" target="_blank">v1.0.0</a> - 2021-06-01
_Initial release._

## v0.1.0 - 2021-04-21
_First lines of code were written as proof of concept, but never published._
