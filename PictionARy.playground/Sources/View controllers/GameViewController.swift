import UIKit
import AVFoundation
import PlaygroundSupport
import GameplayKit
import Vision
import CoreML

public final class GameViewController: UIViewController {
    
    // QoL properties
    fileprivate var previousOrientation: UIDeviceOrientation!
    
    // Music
    private var musicPlayer: AVAudioPlayer?
    private var effectsPlayer: AVAudioPlayer?
    
    // Camera properties
    var captureSession: AVCaptureSession!
    var backCamera: AVCaptureDevice?
    var cameraPreviewLayer: AVCaptureVideoPreviewLayer?
    
    var captureOutput: AVCapturePhotoOutput?
    
    // User interface elements
    private var instructionLabel: UILabel!
    private var centerXConstraint: NSLayoutConstraint?
    private var centerYConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    
    private var scoreLabel: UILabel!
    
    private var timeLabel: UILabel!
    
    private var rateLabel: UILabel?
    
    // Game properties
    let gameDuration = 45
    var timer: Timer?
    
    var currentObject: String?
    var score = 0 {
        didSet {
            self.scoreLabel.text = "Score: \(score)"
        }
    }
    
    var currentObjectIndex = 0 {
        didSet {
            /* Only shuffle the objects when the index is at the maximum.
             
             Advantages:
             * Save CPU power
             * Don't present objects multiple times in a row.
             */
            if currentObjectIndex >= (objects.count - 1) {
                self.currentObjectIndex = 0
                objects = objects.shuffled()
            }
        }
    }
    lazy var objects: [String] = {
        if let path = Bundle.main.path(forResource: "objects", ofType: "txt") {
            do {
                // Try to load the objects from the bundle.
                let url = URL(fileURLWithPath: path)
                let objects = try String(contentsOf: url).split(separator: ",").map({
                    return String($0)
                })
                return objects.shuffled()
            } catch {
                return []
            }
        } else {
            return []
        }
    }()
    
    // Image classification
    lazy var classificationRequest: VNCoreMLRequest? = {
        do {
            if let path = Bundle.main.path(forResource: "Drawings", ofType: "mlmodel") {
                // Load the vision model
                let compiledURL = try MLModel.compileModel(at: URL(fileURLWithPath: path))
                let model = try MLModel(contentsOf: compiledURL)
                let visionModel = try VNCoreMLModel(for: model)
                
                // Create a vision coreml request.
                let request = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                    self.processClassifications(for: request, error: error)
                })
                request.imageCropAndScaleOption = .centerCrop
                return request
            } else {
                mlError("Unable to locate 🧠")
                return nil
            }
        } catch {
            visionError(error.localizedDescription)
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    // MARK: - View controller life cycle
    
    override public func viewDidLoad() {
        // Get notified when the orientation of the device changes.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceRotated),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
        
        // Set the previous orientation to current orientation.
        previousOrientation = UIDevice.current.orientation
        
        // Add tap gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(requestRating))
        self.view.addGestureRecognizer(tapGestureRecognizer)
        
        // Set up the live view from the camera.
        setupCameraPreview()
        
        // Play the music.
        playMusic()
        
        // Set up the labels.
        setupInstructionLabel()
        setupTimeLabel()
        setupScoreLabel()
        
        // Start the game.
        newRound()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        musicPlayer?.stop()
    }

    fileprivate func setupCameraPreview() {
        // Set up the camera session.
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd1280x720
        
        // Set up the video device.
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                      mediaType: AVMediaType.video,
                                                                      position: .back)
        let devices = deviceDiscoverySession.devices
        for device in devices {
            if device.position == AVCaptureDevice.Position.back {
                backCamera = device
            }
        }
        
        // Make sure the actually is a back camera on this particular iPad.
        guard let backCamera = backCamera else {
            cameraError("There seems to be no 📷 on your device. 🥴")
            return
        }
        
        // Set up the input and output stream.
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: backCamera)
            captureSession.addInput(captureDeviceInput)
        } catch {
            cameraError("Your 📷 can't be used as an input device. 😯")
            return
        }
        
        // Initialize the capture output and add it to the session.
        captureOutput = AVCapturePhotoOutput()
        captureOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])], completionHandler: nil)
        captureSession.addOutput(captureOutput!)
        
        // Add a preview layer.
        cameraPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        cameraPreviewLayer!.videoGravity = .resizeAspectFill
        cameraPreviewLayer!.connection?.videoOrientation = .landscapeRight
        cameraPreviewLayer?.frame = view.frame
        
        self.view.layer.insertSublayer(cameraPreviewLayer!, at: 0)
        
        // Start the capture session.
        captureSession.startRunning()
    }
    
    fileprivate func setupInstructionLabel() {
        // Create the instruction label.
        instructionLabel = UILabel()
        instructionLabel.font = UIFont(name: "Chalkduster", size: 26.0)
        instructionLabel.textAlignment = .center
        instructionLabel.textColor = .orange
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add it to the main view.
        self.view.addSubview(instructionLabel)
        
        // Center it horizontally and vertically in the main view.
        // Also add a constraint to position it on the bottom that is not activated [for later use].
        centerYConstraint = instructionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centerXConstraint = instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        bottomConstraint = instructionLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16.0) // The negative sign is correct here; constant is the amount of space moved down additionally.
        NSLayoutConstraint.activate([
            centerXConstraint!,
            centerYConstraint!
            ])
        self.view.layoutIfNeeded()
    }
    
    fileprivate func setupTimeLabel() {
        // Create the time label.
        timeLabel = UILabel()
        timeLabel.font = UIFont(name: "Avenir Next", size: 16.0)
        timeLabel.textAlignment = .center
        timeLabel.textColor = .orange
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add the label to the main view.
        self.view.addSubview(timeLabel)
        
        // Center the label in the top of the view.
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16.0)
            ])
        self.view.layoutIfNeeded()
    }
    
    fileprivate func setupScoreLabel() {
        // Create the score label.
        scoreLabel = UILabel()
        scoreLabel.font = UIFont(name: "Avenir Next", size: 16.0)
        scoreLabel.textAlignment = .center
        scoreLabel.textColor = .orange
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add the label to the main view.
        self.view.addSubview(scoreLabel)
        
        // Position the label in the top left of the view.
        NSLayoutConstraint.activate([
            scoreLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16.0),
            scoreLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16.0)
            ])
        self.view.layoutIfNeeded()
        
        // Set the score to 0
        score = 0
    }
    
    // MARK: - Game methods
    
    func newRound() {
        // Get a new random element from the objects array.
        currentObject = objects[currentObjectIndex]
        currentObjectIndex += 1
        
        // Start playing the sound
        playMusic()

        // Instruct the user. Start counting if the instruction is complete.
        instruct(currentObject!)
        startCounting()
    }
    
    func startCounting() {
        // Make sure only one timer is running at a time.
        timer?.invalidate()
        timer = nil
        
        // Start the timer.
        var currentSecond = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            // Avoid strong reference cycles.
            guard let self = self else { return }
            
            // Increment the timer. If the current second has exceeded the game duration, restart the game, else update the time label.
            currentSecond += 1
            if currentSecond >= self.gameDuration {
                // Stop the game.
                timer.invalidate()
                self.stop()
                self.newRound()
                self.timeLabel.text = "Game Over"
                
                // Play the lose sound.
                self.playSound(named: "lose")
            } else {
                self.timeLabel.text = String(currentSecond)
            }
        }
    }
    
    /// Show an instruction of what to draw to the user.
    ///
    /// - Parameters:
    ///   - drawing: The title of the object.
    ///   - completion: Called when the instruction label has moved down.
    func instruct(_ drawing: String) {
        instructionLabel.isHidden = false
        
        // Clear the position of the current label to avoid unwanted animations.
        centerYConstraint?.isActive = true
        bottomConstraint?.isActive = false
        self.view.layoutIfNeeded()
        
        // Add the drawing instruction.
        let article: String
        if drawing.hasPrefix("a") || drawing.hasPrefix("e") || drawing.hasPrefix("h") || drawing.hasPrefix("i") || drawing.hasPrefix("o") {
            article = "an"
        } else if drawing.hasPrefix("The") {
            article = ""
        } else {
            article = "a"
        }
        instructionLabel.text = "Draw \(article) \(drawing)"
        
        // Present the label in the center for 3 seconds. Then move it to the bottom.
        centerXConstraint?.isActive = true
        centerYConstraint?.isActive = true
        bottomConstraint?.isActive = false
        UIView.animate(withDuration: 2, delay: 0, options: .curveEaseIn, animations: {
            self.view.layoutIfNeeded()
        }) { _ in
            self.centerYConstraint?.isActive = false
            self.bottomConstraint?.isActive = true
            UIView.animate(withDuration: 1, delay: 2, options: .curveEaseIn, animations: {
                self.view.layoutIfNeeded()
            }, completion: nil)
        }
    }
    
    @objc
    func requestRating() {
        stop()
        
        // Capture the output.
        let settings = AVCapturePhotoSettings()
        captureOutput?.capturePhoto(with: settings, delegate: self)
        
        /*
         After the capturing is completed, the didFinishProcessingPhoto
         method will be called. In that method, the classification is updated.
         */
    }
    
    private func rate(withIdentifier identifier: String, confidence: Float) {
        // Grant points.
        let currentScore = Int(confidence * 100)
        score += currentScore
        
        // If the user gets more than 0 points, play a win sound effect - else play lose.
        if currentScore >= 1 {
            playSound(named: "win")
        } else {
            playSound(named: "lose")
        }
        
        // Remove the rate label from the screen.
        rateLabel?.removeFromSuperview()
        
        // Present a message to the user.
        rateLabel = UILabel()
        rateLabel!.translatesAutoresizingMaskIntoConstraints = false
        rateLabel!.font = UIFont(name: "Chalkduster", size: 46.0)
        rateLabel!.textColor = .orange
        rateLabel!.textAlignment = .center
        rateLabel!.text = String(format: "%.2f %", confidence) // C string interpolation to format the confidence score to a more readable format.
        
        self.view.addSubview(rateLabel!)
        
        // Center the rate container view horizonally and vertically.
        NSLayoutConstraint.activate([
            rateLabel!.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            rateLabel!.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            ])
        
        // After 3 seconds, start a new round.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.rateLabel?.removeFromSuperview()
            self.newRound()
        }
    }
    
    /// Stop the current game.
    ///
    /// Sets the time label to nil,
    /// stops the timer, and
    /// centers the instruction label.
    func stop() {
        timeLabel.text = nil
        
        timer?.invalidate()
        timer = nil
        
        instructionLabel.isHidden   = true
        
        bottomConstraint?.isActive  = false
        centerXConstraint?.isActive = true
        centerYConstraint?.isActive = true
        self.view.layoutIfNeeded()
    }
    
    // MARK: - Image classification
    
    func updateClassifications(for image: UIImage) {
        // Create a core image image.
        guard let ciImage = CIImage(image: image) else {
            fatalError("Unable to create \(CIImage.self) from \(image).")
        }
        
        // Perform the classification request on a background thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: CGImagePropertyOrientation.up, options: [:])
            do {
                if let classificationRequest = self.classificationRequest {
                    try handler.perform([classificationRequest])
                }
            } catch {
                self.visionError(error.localizedDescription)
            }
        }
    }
    
    func processClassifications(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            // Check if there are any results. Else show an error alert.
            guard let results = request.results else {
                self.visionError("Couldn't recognize your drawing... 🥺")
                return
            }
            let classifications = results as! [VNClassificationObservation]
            
            if classifications.isEmpty {
                self.visionError("Couldn't recognize your drawing... 🥺")
            } else {
                // Seek for the object to get its confidence.
                // Linear search if faster than performing quicksort and then doing a binary search. Complexity: O(n)
                print(classifications.first!.identifier, classifications.first!.confidence)
                classifications.forEach({ classification in
                    if let currentObject = self.currentObject,
                        classification.identifier == currentObject {
                        
                        // If the intended object is found, show a rating to the user.
                        self.rate(withIdentifier: classification.identifier,
                                  confidence: classification.confidence as Float)
                    }
                })
            }
        }
    }
    
    // MARK: - User interface helpers
    
    /// Present an error alert notifying the user that there was an error with the camera.
    ///
    /// - Parameter message: the custom (playful) error message shown to the user
    private func cameraError(_ message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Error Setting Up 📷", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true)
        }
    }
    
    /// Present an error alert notifying the user that there was an error with vision.
    ///
    /// - Parameter message: the custom (playful) error message shown to the user
    private func visionError(_ message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "My 👓 are dirty", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true)
        }
    }
    
    /// Present an error alert notifying the user that there was an error with machine learning.
    ///
    /// - Parameter message: the custom (playful) error message shown to the user
    private func mlError(_ message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "My 🧠 isn't functioning as expected", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true)
        }
    }
    
    
    @objc
    fileprivate func deviceRotated() {
        // Check previous orientation and compare to prevent unnecessary alerts; this method sometimes gets called if other UI events happen too.
        let currentOrientation = UIDevice.current.orientation
        if currentOrientation != previousOrientation {
            // Display an error.
            let alertController = UIAlertController(title: "Oh no 😵", message: "I'm getting dizzy! Please have the home button on the right hand side.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true)
            
            // Set the previous orientation to the current orienation.
            previousOrientation = currentOrientation
        }
    }
    
    // MARK: - Sounds
    
    func playMusic() {
        // Make sure no music is playing.
        musicPlayer?.stop()
        musicPlayer = nil
        
        if let path = Bundle.main.path(forResource: "music", ofType: "wav") {
            let url = URL(fileURLWithPath: path)
            
            do {
                musicPlayer = try AVAudioPlayer(contentsOf: url)
                musicPlayer?.prepareToPlay()
                musicPlayer?.play()
            } catch {
                musicPlayer = nil
            }
        }
    }
    
    /// Play a sound.
    ///
    /// - Parameter name: the name of the sound in the bundle with type is "wav". (don't include the extension)
    fileprivate func playSound(named name: String) {
        // Pause the music.
        musicPlayer?.pause()
        
        // Stop the current sounds
        effectsPlayer?.stop()
        effectsPlayer = nil
        
        // Play a sound effect.
        if let path = Bundle.main.path(forResource: name,
                                       ofType: "wav") {
            let url = URL(fileURLWithPath: path)

            // Set up an audio player.
            effectsPlayer = try? AVAudioPlayer(contentsOf: url)
            effectsPlayer?.prepareToPlay()
            effectsPlayer?.play()
        }
        
        // Star the music again.
        musicPlayer?.play()
    }
}

extension GameViewController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
            let image = UIImage(data: imageData) {
            
            // Crop the image becuase the video streaming is in another size.
            let frame = CGRect(x: 0, y: 0, width: self.view.frame.height, height: self.view.frame.width) // Flip width and height because the video layer is rotated.
            guard let cgImage = image.cgImage,
                let croppedCGImage = cgImage.cropping(to: frame) else {
                visionError("🖼 is in a straaaange format...")
                return
            }
            
            let croppedImage = UIImage(cgImage: croppedCGImage)
            
            // Update the cropped image.
            updateClassifications(for: croppedImage)
        }
    }
}
