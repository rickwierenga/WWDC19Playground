import UIKit
import AVFoundation

fileprivate enum Direction {
    case next, previous
}

public final class IntroductionViewController: UIViewController {
    
    // Presentation properties
    private let welcomeTexts = [
        ["Welcome to PictionARy 👋", "Swipe right to continue"],
        ["I'll tell you something to draw and then count to 4️⃣5️⃣"],
        ["If you're ✅, get your iPad and scan your 🖼"],
        ["Tap the screen and my 🧠 will rate how you did"],
        ["Now get a piece of 🗒 and a black 🖋", "An iPad Pro with an 🍏 ✏️ works too!"],
        ["All set?!", "[AKA read the tips on the left?]"]
    ]
    private var index = -1
    
    // Current presentation UI elements
    private var currentIntroductionView: UIView?
    
    // Music properties
    private var effectsPlayer: AVAudioPlayer?
    
    // MARK: - View controller life cycle
    
    public override func viewDidLoad() {
        // Add a background.
        self.view.backgroundColor = .white
        
        // Add gesture recognizers.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(presentNext))
        self.view.addGestureRecognizer(tapGestureRecognizer)
        
        let swipeRightGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(presentNext))
        swipeRightGestureRecognizer.direction = .right
        self.view.addGestureRecognizer(swipeRightGestureRecognizer)
        
        let swipeLeftGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(presentPrevious))
        swipeRightGestureRecognizer.direction = .left
        self.view.addGestureRecognizer(swipeLeftGestureRecognizer)
        
        // Start the presentation.
        presentNext()
    }
    
    // MARK: - Presentation
    
    @objc
    func presentNext() {
        present(.next)
    }
    
    @objc
    func presentPrevious() {
        present(.previous)
    }
    
    fileprivate func present(_ direction: Direction) {
        // Get the new index. Make sure the index is not below 0.
        let isNext = direction == .next
        index = max(0, index + (isNext ? 1 : -1))
        
        // Make sure to push the next view controller after all welcome messages have been presented.
        guard index < welcomeTexts.count else {
            if let navigationController = self.navigationController {
                navigationController.pushViewController(GameViewController(), animated: true)
            }
            return
        }
        
        // Remove the current introduction view from the screen.
        currentIntroductionView?.removeFromSuperview()
        
        // Create a new introduction view.
        let introductionView = UIView()
        introductionView.translatesAutoresizingMaskIntoConstraints = false
        introductionView.backgroundColor = .white
        introductionView.layer.backgroundColor = UIColor.white.cgColor
        introductionView.layer.borderWidth = 2
        
        currentIntroductionView = introductionView
        self.view.addSubview(introductionView)
        
        // Create a new label and add it to the current introduction view.
        let mainLabel = UILabel()
        mainLabel.font = UIFont(name: "Chalkduster", size: 26)
        mainLabel.textColor = .black
        mainLabel.textAlignment = .center
        mainLabel.text = welcomeTexts[index][0]
        mainLabel.numberOfLines = 0
        mainLabel.translatesAutoresizingMaskIntoConstraints = false
        
        introductionView.addSubview(mainLabel)
        
        // Position the elements.
        NSLayoutConstraint.activate([
            // Center the introduction view horizontally and vertically. Its width is 80% of the total width.
            introductionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            introductionView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            introductionView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            
            // Position the main label at the top of the introduction view.
            mainLabel.widthAnchor.constraint(equalTo: introductionView.widthAnchor),
            mainLabel.bottomAnchor.constraint(equalTo: introductionView.bottomAnchor),
            ])
        
        // Play a sound
        playSound(named: "click")
        
        // If the current presentation text has a subtitle, display it in dark gray beneath the title.
        if welcomeTexts[index].count == 2 {
            let subLabel = UILabel()
            subLabel.font = UIFont(name: "Chalkduster", size: 14)
            subLabel.textColor = .darkGray
            subLabel.textAlignment = .center
            subLabel.text = welcomeTexts[index][1]
            subLabel.numberOfLines = 0
            subLabel.translatesAutoresizingMaskIntoConstraints = false
            
            introductionView.addSubview(subLabel)
            
            NSLayoutConstraint.activate([
                subLabel.widthAnchor.constraint(equalTo: introductionView.widthAnchor),
                subLabel.topAnchor.constraint(equalTo: introductionView.topAnchor)
                ])
        }
    }
    
    // MARK: - Sounds
    
    /// Play a sound.
    ///
    /// - Parameter name: the name of the sound in the bundle with type is "wav". (don't include the extension)
    fileprivate func playSound(named name: String) {
        if let path = Bundle.main.path(forResource: name,
                                       ofType: "wav") {
            let url = URL(fileURLWithPath: path)
            
            // Set up an audio player.
            effectsPlayer = try? AVAudioPlayer(contentsOf: url)
            effectsPlayer?.prepareToPlay()
            
            effectsPlayer?.play()
        }
    }
}
