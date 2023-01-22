function Set-ProcessProcessorAffinityStatePerCore{

    param(
        [Parameter()][System.Diagnostics.Process]$Process,
        [Parameter()][Int]$Core,
        [Parameter()][bool]$State
    )

    try{
        $AffinityMaskPtr = ( $Process | Select-Object -expandProperty ProcessorAffinity -ErrorAction Ignore)

        if($AffinityMaskPtr -eq $null){
            throw "Couldn't access process ProcessorAffinity field"
        }

    } catch {
        Write-Warning "Unable to process Affinity change on $($Process.Name)[$($Process.ID)]"
        Write-Warning "$($_)"
        return
    }

    $AffinityMask = $AffinityMaskPtr.ToInt64()

    if($State){
        $AffinityMask = (0x1 -shl $Core) -bor $AffinityMask
    } else {
        $AffinityMask = (-bnot (0x1 -shl $Core)) -band $AffinityMask
    }   

    if($AffinityMask -le 0){
        Write-Warning "Did not set affinity on $($Process.Name)[$($Process.Id)] as no cores selected."
    } else{
        Write-Warning "Setting affinity on $($Process.Name)[$($Process.Id)]"
        $Process.ProcessorAffinity = $AffinityMask
    }   
}

function Get-ProcessProcessorAffinityStatePerCore{
    param(
        [Parameter()][System.Diagnostics.Process]$Process,
        [Parameter()][Int]$Core
    )

    try{
        $AffinityMaskPtr = ( $Process | Select-Object -expandProperty ProcessorAffinity -ErrorAction Ignore)
    } catch {
        Write-Warning "Unable to process Affinity change on $($Process.Name)[$($Process.ID)]"
        
        throw "Can't get ProcessorAffinityState"
    }
    if($AffinityMaskPtr -eq $null){
        throw "Couldn't access process ProcessorAffinity field"
    } else {
        $AffinityMask = $AffinityMaskPtr.ToInt64()

        return ((0x1 -shl $Core) -band $AffinityMask) -ne 0
    }
}

function Get-CPUCoreCount{
    #physical cores only.
    #excludes fake hyperthreaded cores
    return (gwmi -query "Select NumberOfCores,NumberOfLogicalProcessors from  Win32_processor").NumberOfCores
}

function Get-LogicalCPUCoreCount {
    #include Hyper Threading.
    return (gwmi -query "Select NumberOfCores,NumberOfLogicalProcessors from  Win32_processor").NumberOfLogicalProcessors
}

function Set-ProcessPriority{
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter()][ValidateSet("Realtime", "High", "AboveNormal", "Normal", "BelowNormal", "Low", "Idle")][string]$PriorityLevel="Normal"
    )

    try
    {
        switch($PriorityLevel){
            "Realtime" {$Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime; break}
            "High" {$Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High; break}
            "AboveNormal" {$Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal; break}
            "Normal" {$Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal; break}
            "BelowNormal" {$Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal; break}
            "Idle" {$Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle; break}

            Default{
                $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal; break
            }
        }
    } catch {
        Write-Warning "Process Priority could not be set on $($Process.Name)[$($Process.ID)]"
    }
}

function Optimize-Process{
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter()][System.Diagnostics.ProcessPriorityClass]$ProcessPriority,
        [Parameter()][int[]]$CoreAllowlist=@("*")
    )

    $TotalCores = Get-LogicalCPUCoreCount

    if($CoreAllowlist[0] -eq "*"){
        for($core = 0; $core -lt $TotalCores; $core++){
            Set-ProcessProcessorAffinityStatePerCore -Process $Process -Core $core -State $true
        }

        if($ProcessPriority -ne $null){
            Set-ProcessPriority -Process $Process -PriorityLevel $ProcessPriority
        }

        return
    }

    for($core = 0; $core -lt $TotalCores; $core++){
        if($core -in $CoreAllowlist){
            Set-ProcessProcessorAffinityStatePerCore -Process $Process -Core $core -State $true
        } else {
            Set-ProcessProcessorAffinityStatePerCore -Process $Process -Core $core -State $false
        }
    }
    
    if($ProcessPriority -ne $null){
        Set-ProcessPriority -Process $Process -PriorityLevel $ProcessPriority
    }
}


function Check-IsProcessAffinityModified{
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

    #Check Process for affinity modifications
    for($core = 0; $core -lt (Get-LogicalCPUCoreCount); $core++){
        try{
        $core_enabled = Get-ProcessProcessorAffinityStatePerCore -Process $process -Core $core
        }
        catch {

            return $false
        }

        if($core_enabled -eq $false){
            return $true
        }
    }

    return $false
}

function Check-ProcessAgainstCoreAllowList{
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter()][int[]]$CoreAllowlist=@("*")
    )

    $TotalCores = Get-LogicalCPUCoreCount

    for($core = 0; $core -lt $TotalCores; $core++){

        try{
            $state = Get-ProcessProcessorAffinityStatePerCore -Process $process -Core $core
        }
        catch {
            
            return $false
        }
        #if enabled then check to see if it's allowed to be enabled.
        if($state){
            if(-not ($core -in $CoreAllowlist)){
                return $false
            }
        }
    }
    
    return $true
}

#Exclude Users
$ExcludedUsers = @("NT AUTHORITY\SYSTEM","NT AUTHORITY\LOCAL SERVICE","NT AUTHORITY\NETWORK SERVICE")

$ExcludedUserDomain = @("Font Driver Host","NT AUTHORITY","Window Manager")

#Use this specifcy certain executables, don't include the file extension. If unsure get what
#powershell "get-process" returns for the Name Property
$ExesToMonitor = @("matlab", "python","comsol","star-ccm+", "starccm+", "starccmw")

#Some software spawns lots of exes and it would be difficult to find and add them all to the allow list
#This will respect anything you can use with the powershell "-like" switch, so some flexability here
$PathsToMonitor = @("C:\SIMULIA\*","C:\Program Files\AnsysEM\*", "C:\Program Files (x86)\CST Studio Suite 2022\*", "C:\Program Files\Lumerical\*")

#If there are applications that still decide to use high core range then lets give them a chance by making 
# our known high demand apps have a lower cpu priority
$DefaultDemandingAppPriorityLevel = [System.Diagnostics.ProcessPriorityClass]::BelowNormal

#for the sim desktop  this will be 5..31
$HighCoreAllowlist = 5..(Get-LogicalCPUCoreCount - 1)


#Most windows programs are designed to run on a few cores, so giving them access to 5 cores is equivelent of a standard computer
#obviously adjust as you see fit.
$LowCoreAllowList = 0..4

#The list below is cherry picked applications that have deemed essential to ensure a decent QoS
#to students during class times.
$ExeToMoveToLowCoreRange = @("rdpclip","rdpinput","explorer", "code", "chrome", "edge", "onedrive", "word", "excel", "logonui"<#, "lsass"#>,"winlogin","startmenuexperiencehost","shellexperiencehost")

#Give these programs a higher priority
$DefaultQoSAppPriorityLevel = [System.Diagnostics.ProcessPriorityClass]::AboveNormal

#Get all processes
Get-Process -IncludeUserName | %{

    $process = $_

    #filter based on users
    if($process.UserName -in $ExcludedUsers){
        Write-Warning "Skipping [$($process.Id)] As owned by $($process.UserName)"
        return
    }

    $ExcludedUserDomain | %{
        if($process.UserName -like "$($_)\*"){
            Write-Warning "Skipping [$($process.Id)] As owned by $($process.UserName)"
            return
        }
    }

    #first lets check the process against known paths.
    $PathsToMonitor | %{
        
        if($process.path -like $_){
            #Some programs already assign core affinity. If the current affinity satisfies the programs CoreAllowList then
            # no need to change. On the otherhand if the affinity is in a bad reagion, force a change.
            if(-not (Check-ProcessAgainstCoreAllowList -Process $process -CoreAllowlist $HighCoreAllowlist)){
                Optimize-Process -Process $process -ProcessPriority $DefaultDemandingAppPriorityLevel -CoreAllowlist $HighCoreAllowlist
            }
        }

    }

    #check process against known executables
    $ExesToMonitor | %{
        if($process.Name -eq $_){
            #Some programs already assign core affinity. If the current affinity satisfies the programs CoreAllowList then
            # no need to change. On the otherhand if the affinity is in a bad reagion, force a change.
            if(-not (Check-ProcessAgainstCoreAllowList -Process $process -CoreAllowlist $HighCoreAllowlist)){
                Optimize-Process -Process $process -ProcessPriority $DefaultDemandingAppPriorityLevel -CoreAllowlist $HighCoreAllowlist
            }
        }
    }


    #lower range processes
    $ExeToMoveToLowCoreRange | %{
        if($process.Name -eq $_){
            #Some programs already assign core affinity. If the current affinity satisfies the programs CoreAllowList then
            # no need to change. On the otherhand if the affinity is in a bad reagion, force a change.
            if(-not (Check-ProcessAgainstCoreAllowList -Process $process -CoreAllowlist $LowCoreAllowList)){
                Optimize-Process -Process $process -ProcessPriority $DefaultQoSAppPriorityLevel -CoreAllowlist $LowCoreAllowList
            }
        }
    }

}





