[CmdletBinding()]
param([switch]$Testing,[switch]$RSS,[switch]$Trends)

<# 

# sudo -u <usr> crontab -e
# Alle 10 Minuten
# */10 * * * * pwsh ~/pwsh/HelloFediverse/hf.ps1
#> # Scripts Notes

#region Script Header v1.1.2
clear-host
set-psdebug -strict
$Error.clear()
$now = get-date -format 'yyyyMMdd_hhmmss'
if (Test-Path "variable:MyInvocation"){
    if($env:OS -like 'Windows_NT'){$mySlash="\"}else{$mySlash="/"}
    $PSScriptPath=split-path -parent $MyInvocation.MyCommand.Definition     #Create $PSScriptPath
    if($Error.count -gt 0){
      Write-Warning "Script need to be saved first. Variable Path `$MyInvocation.MyCommand.Definition is not available"
      $Error
      Break
    }
    $PSScriptName=split-path -Leaf $MyInvocation.MyCommand.Definition       #Create $PSScriptName
    $PSScriptBase=$PSScriptName.Substring(0,$PSScriptName.LastIndexOf(".")) #Create $PSScriptBase
    if(Test-path kjyz-a7sn-o66z-iosc"variable:PSScriptData"){
      if($PSScriptData -eq ""){set-location -LiteralPath $PSScriptPath}
      if($PSScriptData -eq ""){$PSScriptData = ".$mySlash$PSScriptbase(Data)"};if(!(Test-path $PSScriptData)){mkdir $PSScriptData}
    }
    Write-Verbose "Path:$PSScriptPath `r`n Name:$PSScriptName `r`n Base:$PSScriptBase `r`n Data:$PSScriptData `r`n Log:$PSScriptLog"
}else{
    Write-Error "Can not find Variable 'MyInvocation'!";break
}
If ($PSBoundParameters['Debug']) {$DebugPreference = 'Continue'}
if(Test-path "variable:Transcript"){
  If ($Transcript){
    if(Test-path "variable:PSScriptLog"){
      if($PSScriptLog -eq "" ){$PSScriptLog  = ".$mySlash$PSScriptBase(Log)"}
    }else{$PSScriptLog  = ".$mySlash$PSScriptBase(Log)"}
    if(!(Test-path $PSScriptLog)){mkdir $PSScriptLog}
    $logfilename = "$PSScriptLog$mySlash$PSScriptBase($($env:COMPUTERNAME) $Now).log"
    Start-Transcript -LiteralPath $logfilename
  }  
}

$start=get-date
set-location "$psscriptpath"
#endregion
#region Read Password
if(Test-path ./pw.txt.secure){$password=get-content ./pw.txt.secure}
else{
  $password=read-Host "Add Password of User Account 'News@social.mrjeda.de'"
  out-file -InputObject $password -LiteralPath ./pw.txt.secure
}
#endregion
#region Get clientid und clientsecret
if( `
  (test-path ".\clientid.txt.secure") `
  -and (test-path ".\clientsecret.txt.secure")
){
  $clientID    =get-content ".\clientid.txt.secure"
  $clientSecret=get-content ".\clientsecret.txt.secure"
}else{

  $Result = Invoke-WebRequest -Uri https://social.mrjeda.de/api/v1/apps `
    -Body @{
       "client_name"="HelloFediverse"
       "redirect_uris"="urn:ietf:wg:oauth:2.0:oob"
       "scopes"="read,write"
     } -Method Post
   if($Result.StatusCode -ne "200"){Write-Warning "$Return";Exit}
   $result = $result.content|ConvertFrom-Json
   $clientID    =$result."client_ID"
   out-file -InputObject $clientID -LiteralPath ".\clientid.txt.secure"
   $clientSecret=$Result."client_secret"
   out-file -InputObject $clientSecret -LiteralPath ".\clientsecret.txt.secure"   
}
#endregion
#region Get AccessToken
if(test-path ".\accesstoken.txt.secure"){
    $accesstoken = get-content ".\accesstoken.txt.secure"
}else{
$Result3 = Invoke-WebRequest -Uri "https://social.mrjeda.de/oauth/token" `
    -Body @{
        "client_id"="$clientid"
        "client_secret"="$clientsecret"
        "redirect_uris"="urn:ietf:wg:oauth:2.0:oob"
        "scopes"="read,write"
        "grant_type"="password"
        "username"="News"
        "password"="$password"
      } -Method Post
    if($Result3.StatusCode -ne "200"){Write-Warning "$Return";Exit}
    $accesstoken = ($Result3.content|convertfrom-json)."access_token"
    out-file -InputObject $accesstoken -LiteralPath ".\accesstoken.txt.secure"
    $expiresin = ($Result3.content|convertfrom-json)."expires_in"
    out-file -InputObject $expiresin -LiteralPath ".\expires_in.txt"    
}
#endregion

Function MyWebRequest1(){
  [CmdletBinding()]
  param($uri
    ,$file     = ".\response.xml"
    ,$encoding = "utf8"
    )
  Invoke-WebRequest -Uri $uri -OutFile $file|out-null
  get-content $file -Encoding $encoding
} # Web Request over $file
Function MyWebRequest2(){
  [CmdletBinding()]
  param(
    $uri="https://social.mrjeda.de/api/v1/statuses"
    ,$accesstoken
    ,$status
    ,[switch]$testing
    )
  if($Testing){Write-Warning "Testing, `$status will not send to Pleroma Server"}
  else{
    $Resultn = Invoke-WebRequest -Uri "$uri" `
      -Headers @{"Authorization"="Bearer $accesstoken"
      } -Body @{
      "status"="$status"
      } -Method Post
    $Resultn|Select-Object StatusCode,StatusDescription,@{label="Status";expr={$status}}|FT
    }
} # Save $Status on Pleroma Server

function RSSCrawler(){
  [CmdletBinding()]
  param(
   $uri      = "https://newsfeed.zeit.de/"
   ,$Requestfile = ".\response.xml"
   ,$datefile = ".\DieZeit\date.txt" 
   ,$linkfile = ".\DieZeit\link.clixml" # Not used, should disable duplicated statuses with same link
   ,$Headertitle = "DIE ZEIT"
   ,[switch]$linkInnerText
   ,[switch]$titleInnerText
   ,[switch]$descriptionInnerText
   ,[switch]$checkLinkFile              # Not used, should disable duplicated statuses with same link
   ,[switch]$Testing
   )
  $all = $false
  if(Test-path $datefile){$lastdate = Import-Clixml $datefile}else{$all=$true}
  if(Test-path $linkfile){$linkht = Import-Clixml $linkfile}else{$linkht=@{}}
  Write-verbose "RSSCrawler:($all) `$lastdate = $lastdate"
  $headers_tables=@{}
  $headers_tables.Add("content-type", "application/xml; charset=utf-8")

  $laststatus = $false # If to much statuses inside stack, than it might be, that the last stack will not processed.
  $feed1 = MyWebRequest1 -uri $uri -file $RequestFile
  $status = "$Headertitle `r`n `r`n"
  $verbosefirstitem = $true
  ([xml]($feed1))."rss"."channel".SelectNodes("item")|ForEach-Object{
    if($verbosefirstitem){
      $_|out-string|foreach{Write-verbose "$_"}
      $verbosefirstitem=$false
    }   
    $pubdate = get-date $_."pubdate" -format "yyyyMMddTHHmmss"
    if($linkInnerText){$link = $_.link.InnerText}else{$link = $_.link}
    if($titleInnerText){$title = $_.title.InnerText}else{$title = $_.title}
    if($descriptionInnerText){$description = $_.description.InnerText}else{$description = $_.description}
    if(
      ($all -or ($lastdate -lt $pubdate)) `
       -and (
         (!($linkht.contains($link))) `
         -or (!$checklinkFile)
         ) `
      ){
      # New Status to process ...
      Write-verbose "$pubdate $($Title)"
      $laststatus = $true
      $newstatus = $status + " $($Title)`r`n $($link)`r`n $($description) `r`n `r`n"
      write-verbose " $($Title)`r`n $($link)`r`n $($description) `r`n `r`n"

    if($newstatus.length -gt 1000){
      write-host "$Status" -ForegroundColor Cyan
      # Process Status, when 1000 characters reached:
      MyWebRequest2 -accesstoken $accesstoken -testing:$testing -status $status
      $status = "$headertitle `r`n `r`n"
    }else{$status = $status + " $($Title)`r`n $($link)`r`n $($description) `r`n `r`n"}

    if($all -or ($pubdate -gt $lastdate)){
      Export-Clixml -InputObject $pubdate -LiteralPath $datefile
      $lastdate=$pubdate
      }

    if(!($linkht.contains($link))){$linkht.add($link,$pubdate)}
    if($checklinkFile){Export-Clixml -InputObject $linkht -LiteralPath $linkfile}
    } # End of new processed Status

  } # Foreach $statuses
  # Process Last Status
  if($laststatus){
    MyWebRequest2 -accesstoken $accesstoken -testing:$testing -status $status
    }
  out-file -InputObject "Script(RSS.uri=$uri;$($Error.count))"-LiteralPath ".\hf.log" -append
  }
function FediverseTrends(){
    [CmdletBinding()]
    param(
     $server = "INOSOFT.social"
     ,$uri      = "https://inosoft.social/api/v1/trends"
     ,$Requestfile = ".\responseTrends.xml"
     ,[ref]$trendsHT1
     )
    # (Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds(1696809600))
    $global:trend = MyWebRequest1 -uri "$($uri)?limit=20" -file $RequestFile
    if($Error.count -gt 0 ){copy-item -LiteralPath $Requestfile -Destination ".\responseError.xml";$error.clear()}
    write-verbose ""
    ($trend|convertfrom-json).getenumerator()|foreach{
      $uses = $_.History|measure -maximum uses
      $day = $_.History|where{$_.uses -eq $uses.Maximum}|measure -Maximum day
      $item = $_.History|where{$_.day -eq $day.Maximum}
      $max = ((Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds($item.day)))
      if($error.count -ne 0){
        out-file -InputObject "Error in FediverseTrend $uri" -LiteralPath ".\hf.log" -append                
      }
      $name = "$($_.name)"
      $tag = "$(get-date $max -format "yyyy.MM.dd") : $($_.name)"
      $value = "$(get-date $max -format "yyyy.MM.dd"),$server,$($_.name)"
      if([int]([char]($_.name[0])) -lt 254){
        if((get-date -format "yyyy.MM.dd") -eq (get-date $max -format "yyyy.MM.dd")){
          Write-Verbose "$([int]([char]($_.name[0]))) $value"
          if($trendsHT1.value.contains($name)){
            $trendsHT1.value."$name"=@($trendsHT1.value."$name")+@($server)
          }else{$trendsHT1.value.add($name,$server)}
        }else{write-verbose "*$value"}
      }
    }
    out-file -InputObject "Script(Trends.Server=$server;$($Error.count))" -LiteralPath ".\hf.log" -append
  }

if($RSS){
if(!(Test-path ".\DieZeit")){md "DieZeit"}
RSSCrawler -uri "https://newsfeed.zeit.de/" `
  -datefile ".\DieZeit\date.txt" `
  -headertitle ":Zeit: *Die Zeit*" `
  -testing:$testing -Verbose

if(!(Test-path ".\hessenschau")){md "hessenschau"}
RSSCrawler -uri "https://www.hessenschau.de/index.rss" `
   -datefile ".\hessenschau\date.txt" `
   -headertitle ":hessen: *Hessenschau*" `
   -linkInnerText -testing:$testing -verbose

if(!(Test-path ".\OP")){md "OP"}
RSSCrawler -uri "https://www.op-marburg.de/arc/outboundfeeds/rss/" `
   -datefile ".\OP\date.txt" `
   -headertitle ":op: *Oberhessische Presse*" `
   -titleInnerText -descriptionInnerText -testing:$testing -verbose

if(!(Test-path ".\sge")){md "sge"}
RSSCrawler -uri "https://profis.eintracht.de/rss/feed.xml" `
   -datefile ".\sge\date.txt" `
   -headertitle ":sge: *Eintracht Frankfurt*" `
   -titleInnerText -descriptionInnerText -testing:$testing -verbose

if(!(Test-path ".\ukr")){md "ukr"}
RSSCrawler -uri "https://www.ukrinform.net/rss/block-lastnews" `
   -datefile ".\ukr\date.txt" `
   -headertitle ":ukr: *ukrinform*" `
   -titleInnerText -descriptionInnerText -testing:$testing -verbose

if(!(Test-path ".\ino")){md "ino"}
RSSCrawler -uri "https://www.inosoft.de/feed/news.rss?style=0" `
   -datefile ".\ino\date.txt" `
   -headertitle ":ino: *INOSOFT*" `
   -titleInnerText -descriptionInnerText -testing:$testing -verbose
}
if($Trends){
  $trendsHT1=@{} # Trends Overall
  FediverseTrends -server "inosoft.." `
   -uri "https://inosoft.social/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 
  FediverseTrends -server "mastodon.." `
   -uri "https://mastodon.social/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 
  FediverseTrends -server "chaos.." `
   -uri "https://chaos.social/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 
  FediverseTrends -server "..bund.de" `
   -uri "https://social.bund.de/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 
  FediverseTrends -server "troet.cafe" `
   -uri "https://troet.cafe/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 
  FediverseTrends -server "det.." `
   -uri "https://det.social/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 
   FediverseTrends -server "mstdn.." `
   -uri "https://mstdn.social/api/v1/trends" `
   -trendsHT1 ([ref]$trendsHT1) -verbose 

  $length = ($trendsHT1.GetEnumerator()|foreach{$_.name.length}|measure -Maximum).Maximum
  
  $status="**Trends** `r`n`r`n"
  $trendsHT1.GetEnumerator()|foreach{
    $status = $Status + "$($_.name.padright($length," ")) : $(($_.value|sort) -join " ")`r`n"
  }
  $status = $Status + "Links:`r`n- https://fedidb.org/"
  MyWebRequest2 -accesstoken $accesstoken -testing:$testing -status $status
}

$end = Get-Date
$Diff = ($end-$start)
$done = "Script(RSS=$RSS;Trends=$trends) processed at $start in $Diff seconds."
Write-host $done
out-file -InputObject $done -LiteralPath ".\hf.log" -append
