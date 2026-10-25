param([string]$GodotPath = '', [switch]$Window)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
$engine = Resolve-Godot $GodotPath
$project = Join-Path (Split-Path $PSScriptRoot -Parent) 'game'
$logs = Join-Path (Split-Path $PSScriptRoot -Parent) '.local/test-results'
New-Item -ItemType Directory -Path $logs -Force | Out-Null

function Invoke-EngineCheck([string]$Name, [string[]]$EngineArgs, [string]$Marker) {
    $output = & $engine @EngineArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $logs "$Name.log") -Encoding utf8
    if ($code -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:|^FAIL' -or ($Marker -and -not $output.Contains($Marker))) {
        Write-Host $output
        throw "Check failed: $Name (exit $code)"
    }
    Write-Host "PASS $Name"
}

Invoke-EngineCheck 'import' @('--headless', '--path', $project, '--editor', '--import') ''
foreach ($suite in @('input', 'radio', 'controls', 'hud_audio', 'rotor_audio', 'field_tasks', 'flow_routes', 'acro_routes', 'continuous_routes', 'spatial_routes', 'navigation_preview', 'refinement', 'cave_seams', 'race_guide', 'regional_world', 'expansion', 'challenge_feedback', 'mission_replay', 'gameplay', 'handling', 'audio', 'entrance', 'actions', 'tuning', 'map', 'missions', 'content', 'world', 'streaming', 'scenery', 'regions', 'discovery', 'playability', 'developer', 'exploration', 'flight', 'integration', 'about')) {
    $marker = if ($suite -eq 'flight') { 'FLIGHT_TESTS: 0 failure(s)' } elseif ($suite -eq 'regional_world') { 'REGIONAL_RESULT failures=0' } else { "$($suite.ToUpper())_RESULT failures=0" }
    $quitFrames = if ($suite -in @('refinement', 'regional_world', 'cave_seams', 'race_guide', 'acro_routes', 'continuous_routes', 'spatial_routes', 'navigation_preview', 'streaming')) { '150000' } elseif ($suite -in @('handling', 'playability', 'gameplay', 'mission_replay', 'field_tasks', 'expansion')) { '15000' } else { '5000' }
    Invoke-EngineCheck $suite @('--headless', '--path', $project, '--script', "res://tests/${suite}_tests.gd", '--quit-after', $quitFrames, '--', '--test-session') $marker
}
Invoke-EngineCheck 'smoke' @('--headless', '--path', $project, '--quit-after', '1800', '--', '--smoke') 'SMOKE_OK'
if ($Window) {
	Invoke-EngineCheck 'city-render-window' @('--path', $project, '--script', 'res://tests/city_render_tests.gd', '--quit-after', '150000', '--', '--test-session') 'CITY_RENDER_RESULT failures=0'
	Invoke-EngineCheck 'about-window' @('--path', $project, '--script', 'res://tests/about_tests.gd', '--quit-after', '15000', '--', '--test-session') 'ABOUT_RESULT failures=0'
	Invoke-EngineCheck 'streaming-window' @('--path', $project, '--script', 'res://tests/streaming_tests.gd', '--quit-after', '150000', '--', '--test-session') 'STREAMING_RESULT failures=0'
    Invoke-EngineCheck 'navigation-preview-window' @('--path', $project, '--script', 'res://tests/navigation_preview_tests.gd', '--quit-after', '150000', '--', '--test-session', "--capture-dir=$logs/navigation-preview") 'NAVIGATION_PREVIEW_RESULT failures=0'
    Invoke-EngineCheck 'race-guide-window' @('--path', $project, '--script', 'res://tests/race_guide_tests.gd', '--quit-after', '150000', '--', '--test-session', "--capture-dir=$logs/race-guide") 'RACE_GUIDE_RESULT failures=0'
    Invoke-EngineCheck 'continuous-routes-window' @('--path', $project, '--script', 'res://tests/continuous_routes_tests.gd', '--quit-after', '150000', '--', '--test-session') 'CONTINUOUS_ROUTES_RESULT failures=0'
    Invoke-EngineCheck 'spatial-routes-window' @('--path', $project, '--script', 'res://tests/spatial_routes_tests.gd', '--quit-after', '150000', '--', '--test-session') 'SPATIAL_ROUTES_RESULT failures=0'
    Invoke-EngineCheck 'refinement-visual-window' @('--path', $project, '--script', 'res://tests/refinement_visual_tests.gd', '--quit-after', '40000', '--', '--test-session', "--capture-dir=$logs/refinement-visual") 'REFINEMENT_VISUAL_RESULT failures=0'
    Invoke-EngineCheck 'regional-visual-window' @('--path', $project, '--script', 'res://tests/regional_visual_tests.gd', '--quit-after', '40000', '--', '--test-session', "--capture-dir=$logs/regional-visual") 'REGIONAL_VISUAL_RESULT failures=0'

	Invoke-EngineCheck 'follow-live-window' @('--path', $project, '--script', 'res://tests/follow_live_tests.gd', '--quit-after', '10000', '--', '--test-session', "--capture-dir=$logs/follow-live") 'FOLLOW_LIVE_RESULT failures=0'
	Invoke-EngineCheck 'expansion-tour-window' @('--path', $project, '--script', 'res://tests/expansion_tour_tests.gd', '--quit-after', '40000', '--', '--test-session', "--capture-dir=$logs/expansion-tour") 'EXPANSION_TOUR_RESULT failures=0'
	Invoke-EngineCheck 'expansion-window' @('--path', $project, '--script', 'res://tests/expansion_tests.gd', '--quit-after', '30000', '--', '--test-session', "--capture-dir=$logs/expansion") 'EXPANSION_RESULT failures=0'
	Invoke-EngineCheck 'challenge-feedback-window' @('--path', $project, '--script', 'res://tests/challenge_feedback_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/challenge-feedback") 'CHALLENGE_FEEDBACK_RESULT failures=0'
	Invoke-EngineCheck 'field-tasks-window' @('--path', $project, '--script', 'res://tests/field_tasks_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/field-tasks") 'FIELD_TASKS_RESULT failures=0'
	Invoke-EngineCheck 'mission-replay-window' @('--path', $project, '--script', 'res://tests/mission_replay_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/mission-replay") 'MISSION_REPLAY_RESULT failures=0'
	Invoke-EngineCheck 'gameplay-window' @('--path', $project, '--script', 'res://tests/gameplay_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/gameplay") 'GAMEPLAY_RESULT failures=0'
	Invoke-EngineCheck 'rotor-audio-window' @('--path', $project, '--script', 'res://tests/rotor_audio_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs/rotor-audio") 'ROTOR_AUDIO_RESULT failures=0'
	Invoke-EngineCheck 'hud-audio-window' @('--path', $project, '--script', 'res://tests/hud_audio_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs/hud-audio") 'HUD_AUDIO_RESULT failures=0'
	Invoke-EngineCheck 'controls-window' @('--path', $project, '--script', 'res://tests/controls_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/controls") 'CONTROLS_RESULT failures=0'
	Invoke-EngineCheck 'handling-window' @('--path', $project, '--script', 'res://tests/handling_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/handling-window") 'HANDLING_RESULT failures=0'
	Invoke-EngineCheck 'audio-window' @('--path', $project, '--script', 'res://tests/audio_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/audio") 'AUDIO_RESULT failures=0'
	Invoke-EngineCheck 'entrance-window' @('--path', $project, '--script', 'res://tests/entrance_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/entrance") 'ENTRANCE_RESULT failures=0'
    Invoke-EngineCheck 'exploration-window' @('--path', $project, '--script', 'res://tests/exploration_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/exploration") 'EXPLORATION_RESULT failures=0'
    Invoke-EngineCheck 'developer-window' @('--path', $project, '--script', 'res://tests/developer_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/developer") 'DEVELOPER_RESULT failures=0'
    Invoke-EngineCheck 'playability-window' @('--path', $project, '--script', 'res://tests/playability_tests.gd', '--quit-after', '15000', '--', '--test-session', "--capture-dir=$logs/playability") 'PLAYABILITY_RESULT failures=0'
    Invoke-EngineCheck 'discovery-window' @('--path', $project, '--script', 'res://tests/discovery_tests.gd', '--quit-after', '9000', '--', '--test-session', "--capture-dir=$logs/discovery") 'DISCOVERY_RESULT failures=0'
    Invoke-EngineCheck 'regions-window' @('--path', $project, '--script', 'res://tests/regions_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs/regions") 'REGIONS_RESULT failures=0'
    Invoke-EngineCheck 'scenery-window' @('--path', $project, '--script', 'res://tests/scenery_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs/world-detail") 'SCENERY_RESULT failures=0'
    Invoke-EngineCheck 'missions-window' @('--path', $project, '--script', 'res://tests/missions_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs") 'MISSIONS_RESULT failures=0'
    Invoke-EngineCheck 'map-window' @('--path', $project, '--script', 'res://tests/map_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs") 'MAP_RESULT failures=0'
    Invoke-EngineCheck 'radio-window' @('--path', $project, '--script', 'res://tests/radio_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs") 'RADIO_RESULT failures=0'
    Invoke-EngineCheck 'actions-window' @('--path', $project, '--script', 'res://tests/actions_tests.gd', '--quit-after', '5000', '--', '--test-session') 'ACTIONS_RESULT failures=0'
    Invoke-EngineCheck 'tuning-window' @('--path', $project, '--script', 'res://tests/tuning_tests.gd', '--quit-after', '5000', '--', '--test-session', "--capture-dir=$logs") 'TUNING_RESULT failures=0'
    Invoke-EngineCheck 'window-tour' @('--path', $project, '--quit-after', '3000', '--', '--tour', "--capture-dir=$logs") 'SMOKE_OK'
}
Write-Host "All checks passed. Logs: $logs"
