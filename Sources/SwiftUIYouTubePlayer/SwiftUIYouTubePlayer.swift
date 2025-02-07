import SwiftUI
import SwiftUIWebView

public enum YouTubePlayerAction: Equatable {
    case idle,
         loadURL(URL),
         loadID(String),
         loadPlaylistID(String),
         mute,
         unmute,
         play,
         pause,
         stop,
         clear,
         seek(Float, Bool),
         duration,
         currentTime,
         previous,
         next
}

public enum YouTubePlayerStatus: String, Equatable {
    case unstarted = "-1",
         ended = "0",
         playing = "1",
         paused = "2",
         buffering = "3",
         queued = "4"
}

public enum YouTubePlayerEvents: String, Equatable {
    case youTubeIframeAPIReady = "onYouTubeIframeAPIReady",
         ready = "onReady",
         statusChange = "onStateChange",
         playbackQualityChange = "onPlaybackQualityChange"
}

public enum YouTubePlaybackQuality: String, Equatable {
    case small = "small",
         medium = "medium",
         large = "large",
         hd720 = "hd720",
         hd1080 = "hd1080",
         highResolution = "highres"
}

typealias YouTubePlayerParams = [String: AnyObject]

public struct YouTubePlayerState: Equatable {
    public internal(set) var ready: Bool
    public internal(set) var status: YouTubePlayerStatus
    public internal(set) var quality: YouTubePlaybackQuality
    public internal(set) var duration: Double?
    public internal(set) var currentTime: Double?
    public internal(set) var error: Error?
    internal var iframeReady: Bool
    
    public static let empty = YouTubePlayerState(ready: false,
                                                 status: .unstarted,
                                                 quality: .small,
                                                 duration: nil,
                                                 currentTime: nil,
                                                 error: nil,
                                                 iframeReady: false)
    
    public static func == (lhs: YouTubePlayerState, rhs: YouTubePlayerState) -> Bool {
        lhs.ready == rhs.ready
            && lhs.status == rhs.status
            && lhs.quality == rhs.quality
            && lhs.duration == rhs.duration
            && lhs.currentTime == rhs.currentTime
            && lhs.error?.localizedDescription == rhs.error?.localizedDescription
            && lhs.iframeReady == rhs.iframeReady
    }
}

public struct YouTubePlayerConfig {
    let playInline: Bool
    let allowControls: Bool
    let showInfo: Bool
    
    public init(playInline: Bool,
                allowControls: Bool,
                showInfo: Bool) {
        self.playInline = playInline
        self.allowControls = allowControls
        self.showInfo = showInfo
    }
    
    public static let `default` = YouTubePlayerConfig(playInline: true,
                                                      allowControls: false,
                                                      showInfo: false)
}

/** Embed and control YouTube videos */
public struct YouTubePlayer: View {
    private static let webViewConfig = WebViewConfig(javaScriptEnabled: true,
                                                     allowsBackForwardNavigationGestures: false,
                                                     allowsInlineMediaPlayback: true,
                                                     isScrollEnabled: false,
                                                     isOpaque: true,
                                                     backgroundColor: .clear)
    private static let playerHTML = """
        <!DOCTYPE html>
        <html>
            <head>
                <style>
                    * { margin: 0; padding: 0; }
                    html, body { width: 100%; height: 100%; }
                </style>
            </head>
            <body>
                <div id="player"></div>
                <script src="https://www.youtube.com/iframe_api"></script>
                <script>
                    var player;
                    YT.ready(function() {
                             player = new YT.Player('player', %@);
                             window.location.href = 'ytplayer://onYouTubeIframeAPIReady';
                             });
                             function onReady(event) {
                                 window.location.href = 'ytplayer://onReady?data=' + event.data;
                             }

                function onStateChange(event) {
                    window.location.href = 'ytplayer://onStateChange?data=' + event.data;
                }

                function onPlaybackQualityChange(event) {
                    window.location.href = 'ytplayer://onPlaybackQualityChange?data=' + event.data;
                }
                function onPlayerError(event) {
                    window.location.href = 'ytplayer://onError?data=' + event.data;
                }
                </script>
            </body>
        </html>
        """
    private static let getDurationCommand = "getDuration()"
    private static let getCurrentTimeCommand = "getCurrentTime()"
    
    @Binding var action: YouTubePlayerAction
    @Binding var state: YouTubePlayerState
    
    @State private var webViewAction = WebViewAction.idle
    @State private var webViewState = WebViewState.empty
    @State private var playerVars: YouTubePlayerParams = [:]
    
    public init(action: Binding<YouTubePlayerAction>,
                state: Binding<YouTubePlayerState>,
                config: YouTubePlayerConfig = .default) {
        _action = action
        _state = state
        playerVars = ["playsinline": config.playInline ? "1" : "0",
                      "controls":  config.allowControls ? "1" : "0",
                      "showinfo":  config.showInfo ? "1" : "0"
        ] as YouTubePlayerParams
    }

    public var body: some View {
        WebView(config: YouTubePlayer.webViewConfig,
                action: $webViewAction,
                state: $webViewState,
                schemeHandlers: ["ytplayer": handleJSEvent(_:)])
            .onChange(of: action, perform: handleAction(_:))
//            .onChange(of: webViewState, perform: handleWebViewStateChange(_:))
    }
    
    private func handleAction(_ value: YouTubePlayerAction) {
        if value == .idle {
            return
        }
        switch value {
        case .idle:
            break
        case .loadURL(let url):
            if let id = videoIDFromYouTubeURL(url) {
                loadVideo(id: id)
            } else {
                onError(URLError(.badURL))
            }
        case .loadID(let id):
            loadVideo(id: id)
        case .loadPlaylistID(let id):
            // No videoId necessary when listType = playlist, list = [playlist Id]
            playerVars["listType"] = "playlist" as AnyObject?
            playerVars["list"] = id as AnyObject?
            loadWebViewWithParameters(defaultPlayerParams)
        case .mute:
            evaluatePlayerCommand("mute()")
        case .unmute:
            evaluatePlayerCommand("unMute()")
        case .play:
            evaluatePlayerCommand("playVideo()")
        case .pause:
            evaluatePlayerCommand("pauseVideo()")
        case .stop:
            evaluatePlayerCommand("stopVideo()")
        case .clear:
            evaluatePlayerCommand("clearVideo()")
        case .seek(let seconds, let seekAhead):
            evaluatePlayerCommand("seekTo(\(seconds), \(seekAhead))")
        case .duration:
            evaluatePlayerCommand(YouTubePlayer.getDurationCommand) { result in
                if let value = result as? Double {
                    var newState = state
                    newState.duration = value
                    state = newState
                }
            }
        case .currentTime:
            evaluatePlayerCommand(YouTubePlayer.getCurrentTimeCommand) { result in
                if let value = result as? Double {
                    var newState = state
                    newState.currentTime = value
                    state = newState
                }
            }
        case .previous:
            evaluatePlayerCommand("previousVideo()")
        case .next:
            evaluatePlayerCommand("nextVideo()")
        }
        action = .idle
    }
    
    private func onError(_ error: Error) {
        var newState = state
        newState.error = error
        state = newState
    }
    
    private func loadVideo(id: String) {
        var params = defaultPlayerParams
        params["videoId"] = id as AnyObject?
        loadWebViewWithParameters(params)
    }

    private func evaluatePlayerCommand(_ command: String, callback: ((Any?) -> Void)? = nil) {
        let fullCommand = "player.\(command);"
        webViewAction = .evaluateJS(fullCommand, { result in
            switch result {
            case .success(let value):
                callback?(value)
            case .failure(let error):
                if (error as NSError).code == 5 { // NOTE: ignore :Void return
                    callback?(nil)
                } else {
                    onError(error)
                }
            }
        })
    }

    // MARK: Player setup
    private func loadWebViewWithParameters(_ parameters: YouTubePlayerParams) {
        let rawHTMLString = YouTubePlayer.playerHTML
        // Get JSON serialized parameters string
        let jsonParameters = serializedJSON(parameters as AnyObject)!
        // Replace %@ in rawHTMLString with jsonParameters string
        let htmlString = rawHTMLString.replacingOccurrences(of: "%@", with: jsonParameters)
        // Load HTML in web view
        webViewAction = .loadHTML(htmlString)
    }

    // MARK: Player parameters and defaults
    private var defaultPlayerParams: YouTubePlayerParams {
        ["height": "100%" as AnyObject,
         "width": "100%" as AnyObject,
         "events": playerCallbacks as AnyObject,
         "playerVars": playerVars as AnyObject
        ]
    }

    private var playerCallbacks: YouTubePlayerParams {
       ["onReady": "onReady" as AnyObject,
        "onStateChange": "onStateChange" as AnyObject,
        "onPlaybackQualityChange": "onPlaybackQualityChange" as AnyObject,
        "onError": "onPlayerError" as AnyObject
       ]
    }

    private func serializedJSON(_ object: AnyObject) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let string = String(data: jsonData, encoding: .utf8)
        else {
            return nil
        }
        return string
    }


    // MARK: JS Event Handling
    private func handleJSEvent(_ eventURL: URL) {
        // Grab the last component of the queryString as string
        let data: String? = eventURL.queryStringComponents()["data"] as? String
        if let host = eventURL.host, let event = YouTubePlayerEvents(rawValue: host) {
            // Check event type and handle accordingly
            switch event {
            case .youTubeIframeAPIReady:
                var newState = state
                newState.iframeReady = true
                state = newState
            case .ready:
                var newState = state
                newState.ready = true
                state = newState
            case .statusChange:
                if let newStatus = YouTubePlayerStatus(rawValue: data!) {
                    var newState = state
                    newState.status = newStatus
                    state = newState
                }
            case .playbackQualityChange:
                if let newQuality = YouTubePlaybackQuality(rawValue: data!) {
                    var newState = state
                    newState.quality = newQuality
                    state = newState
                }
            }
        }
    }
}

private extension URL {
    func queryStringComponents() -> [String: AnyObject] {

        var dict = [String: AnyObject]()

        // Check for query string
        if let query = self.query {

            // Loop through pairings (separated by &)
            for pair in query.components(separatedBy: "&") {

                // Pull key, val from from pair parts (separated by =) and set dict[key] = value
                let components = pair.components(separatedBy: "=")
                if (components.count > 1) {
                    dict[components[0]] = components[1] as AnyObject?
                }
            }

        }

        return dict
    }
}

private func videoIDFromYouTubeURL(_ videoURL: URL) -> String? {
    if videoURL.pathComponents.count > 1 && (videoURL.host?.hasSuffix("youtu.be"))! {
        return videoURL.pathComponents[1]
    } else if videoURL.pathComponents.contains("embed") {
        return videoURL.pathComponents.last
    }
    return videoURL.queryStringComponents()["v"] as? String
}

struct YouTubeTest: View {
    @State private var action = YouTubePlayerAction.idle
    @State private var state = YouTubePlayerState.empty
    
    private var buttonText: String {
        switch state.status {
        case .playing:
            return "Pause"
        case .unstarted,  .ended, .paused:
            return "Play"
        case .buffering, .queued:
            return "Wait"
        }
    }
    private var infoText: String {
        "Q: \(state.quality)"
    }
    
    var body: some View {
        VStack {
            HStack {
                Button("Load") {
                    action = .loadID("v1PBptSDIh8")
                }
                Button(buttonText) {
                    if state.status != .playing {
                        action = .play
                    } else {
                        action = .pause
                    }
                }
                Text(infoText)
                Button("Prev") {
                    action = .previous
                }
                Button("Next") {
                    action = .next
                }
            }
            YouTubePlayer(action: $action, state: $state)
            Spacer()
        }
    }
}

struct YouTubePlayer_Previews: PreviewProvider {
    static var previews: some View {
        YouTubeTest()
    }
}
