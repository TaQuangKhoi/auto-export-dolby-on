# ===================================================================
# CONFIG.PS1 - Configuration Settings
# ===================================================================
# Contains all app-specific constants and timing configurations

$script:Config = @{
    # Feature flags
    EnableDump = $false
    EnableReport = $true
    
    # Paths
    DumpsFolder = "dumps"
    
    # Wait times (seconds)
    WaitTimes = @{
        AppStabilize = 2
        ScreenLoad = 2
        PopupAppear = 2
        SaveDialog = 3
    }
    
    # Dolby On App Configuration
    DolbyApp = @{
        Package = "com.dolby.dolby234"
        
        # Resource IDs for UI elements
        ResourceIds = @{
            # Library Screen
            RecyclerView = "com.dolby.dolby234:id/library_items_recycler_view"
            TrackItem = "com.dolby.dolby234:id/swipe_layout"
            Title = "com.dolby.dolby234:id/title_text_view"
            Date = "com.dolby.dolby234:id/date_text_view"
            Time = "com.dolby.dolby234:id/time_text_view"
            
            # Detail Screen
            ShareButton = "com.dolby.dolby234:id/track_details_share"
            
            # Share Popup
            ExportLossless = "com.dolby.dolby234:id/share_option_lossless_audio_item"
        }
    }
    
    # Android System
    AndroidSystem = @{
        DocumentsUiPackage = "com.android.documentsui"
        SaveButtonText = "Save"
    }
}

function Get-Config {
    return $script:Config
}
