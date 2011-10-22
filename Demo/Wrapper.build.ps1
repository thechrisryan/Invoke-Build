
<#
.Synopsis
	Tests the wrapper script Build.ps1.

.Example
	Invoke-Build . Wrapper.build.ps1
#>

# Skip all preparations on WhatIf calls (when Tree and Comment are tested).
# Well written scripts should do this check and skip unwanted actions.
if (!$WhatIf) {
	# Build.ps1 can be invoked as ..\Build.ps1 from this script tasks. But we use
	# the alias set but 'use' instead, just in order to show that 'use' works not
	# only for .NET framework directory tools but for any tools, scripts as well.
	use .. Build

	# Make directories in here (many build files) and in the parent (one file).
	Remove-Item [z] -Force -Recurse
	$null = mkdir z\1\2

	# This directory has many build files, the default is
	$ManyDefault = $PSCmdlet.GetUnresolvedProviderPathFromPSPath('.build.ps1')

	# This path will represent a single build file
	$OneDefault = "$BuildRoot\z\test.build.ps1"
}

task ParentHasManyCandidates {
	Set-Location z
	$PWD.Path
	$log = Build ?
	$log
	assert ($log[0].StartsWith("Build ? $ManyDefault"))
}

task GrandParentHasManyCandidates {
	Set-Location z\1
	$PWD.Path
	$log = Build ?
	$log
	assert ($log[0].StartsWith("Build ? $ManyDefault"))
}

task MakeSingleScript {
	'task .' > z\test.build.ps1
}

task ParentHasOneCandidate MakeSingleScript, {
	Set-Location z\1
	$PWD.Path
	$log = Build ?
	$log
	assert ($log[0].StartsWith("Build ? $OneDefault"))
}

task GrandParentHasOneCandidate MakeSingleScript, {
	Set-Location z\1\2
	$PWD.Path
	$log = Build ?
	$log
	assert ($log[0].StartsWith("Build ? $OneDefault"))
}

task InvokeBuildGetFile {
	# register the hook by the environment variable
	$saved = $env:InvokeBuildGetFile
	$env:InvokeBuildGetFile = "$BuildRoot\z\1\InvokeBuildGetFile.ps1"

	# make the hook script which gets a build file
	#! `> $env:InvokeBuildGetFile` fails in [ ]
	$path = "$BuildRoot\Property.build.ps1"
	[System.IO.File]::WriteAllText($env:InvokeBuildGetFile, "'$path'")

	# invoke (remove the test script, if any)
	Set-Location z
	Remove-Item test.build.ps1 -ErrorAction 0
	$PWD.Path
	$log = Build ?
	$log

	# restore the hook
	$env:InvokeBuildGetFile = $saved

	# test: the script returned by the hook is invoked
	assert ($log[0].StartsWith("Build ? $path"))
}

task Tree {
	# no task
	$log = Build -File Wrapper.build.ps1 -Tree | Out-String
	$log
	assert ($log -like '*ParentHasManyCandidates (.)*TreeAndComment (.)*    Tree (TreeAndComment)*        Tree (TreeAndComment)*')
	assert (!$log.Contains('#'))

	# ? task has the same effect
	$log2 = Build -File Wrapper.build.ps1 -Tree | Out-String
	assert ($log2 -eq $log)
}

task Comment {
	# -Comment works on its own
	$log = Build . Wrapper.build.ps1 -Comment | Out-String
	$log

	# -Comment works with -Tree with the same effect
	$log2 = Build . Wrapper.build.ps1 -Tree -Comment | Out-String
	assert ($log2 -eq $log)

	# ensure comments are there
	$log = $log -replace '\r\n', '='
	assert ($log.Contains('\Wrapper.build.ps1==# Call tests and clean.=# The comment is tested.=.=    ParentHasManyCandidates (.)=')) $log
	assert ($log.Contains('=    <#=    Call tree tests.=    The comment is tested.=    #>=    TreeAndComment (.)=        Tree (TreeAndComment)=')) $log
}

<#
Call tree tests.
The comment is tested.
#>
task TreeAndComment Tree, Comment

task Summary {
	# fake
	function Write-Host($Text, $ForegroundColor) { $null = $log.Add($Text) }

	# build succeeds
	@'
task task1 { Start-Sleep -Milliseconds 1 }
task . task1
'@ > z\test.build.ps1
	$log = [System.Collections.ArrayList]@()
	Build . z\test.build.ps1 -Summary
	$log = ($log -join "`r`n")
	Write-BuildText Magenta $log
	assert ($log -like '00:00:00*task1*\z\test.build.ps1:1*00:00:00*.*\z\test.build.ps1:2')

	# build fails
	@'
task task1 { throw 'Demo error in task1.' }
task . @{task1=1}
'@ > z\test.build.ps1
	$log = [System.Collections.ArrayList]@()
	Build . z\test.build.ps1 -Summary
	$log = ($log -join "`r`n")
	Write-BuildText Magenta $log
	assert ($log -like '00:00:00*task1*\z\test.build.ps1:1*Demo error in task1.*00:00:00*.*\z\test.build.ps1:2')
}

task TreeTaskNotDefined {
	[System.IO.File]::WriteAllText("$BuildRoot\z\test.build.ps1", {
		task task1 missing, {}
		task . task1, {}
	})
	Build . z\test.build.ps1 -Tree
}

task TreeCyclicReference {
	[System.IO.File]::WriteAllText("$BuildRoot\z\test.build.ps1", {
		task task1 task2
		task task2 task1
		task . task1
	})
	Build . z\test.build.ps1 -Tree
}

# Call tests and clean.
# The comment is tested.
task . `
ParentHasManyCandidates,
GrandParentHasManyCandidates,
ParentHasOneCandidate,
GrandParentHasOneCandidate,
InvokeBuildGetFile,
TreeAndComment,
Summary,
@{TreeTaskNotDefined=1},
@{TreeCyclicReference=1},
{
	$e = error TreeTaskNotDefined
	assert ("$e" -like "Task 'task1': Task 'missing' is not defined.*At *\z\test.build.ps1:*task <<<<  task1 *")

	$e = error TreeCyclicReference
	assert ("$e" -like "Task 'task2': Cyclic reference to 'task1'.*At *\z\test.build.ps1:*task <<<<  task2 *")

	Remove-Item z -Force -Recurse
}
