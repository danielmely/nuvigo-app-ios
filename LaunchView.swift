import SwiftUI

/// Start-up screen: logo and a loading bar while the app gets everything ready.
struct LaunchView: View {
    @ObservedObject var preloader: Preloader
    @State private var lines = LaunchLines.shuffled()
    @State private var lineIndex = 0
    @State private var lineOpacity = 0.0
    /// The saved Appearance setting (it syncs with the account); "system" follows the phone.
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme { (AppearanceMode(rawValue: appearance) ?? .system).scheme ?? systemScheme }

    var body: some View {
        ZStack {
            LogoData.background(for: scheme).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                if let logo = LogoData.image(for: scheme) {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300)
                } else {
                    Text("NuviGo").font(.largeTitle.weight(.bold)).foregroundStyle(scheme == .dark ? Color.white : Color.black)
                }
                Text(preloader.refreshing ? " " : lines[lineIndex])
                    .font(.callout.italic())
                    .multilineTextAlignment(.center)
                    .foregroundStyle((scheme == .dark ? Color.white : Color.black).opacity(0.8))
                    .frame(maxWidth: 300, minHeight: 60)
                    .opacity(lineOpacity)
                Spacer()
                VStack(spacing: 10) {
                    ProgressView(value: preloader.progress)
                        .progressViewStyle(.linear)
                        .tint(Color(red: 0.70, green: 0.0, blue: 1.0))
                    Text(preloader.status)
                        .font(.footnote)
                        .foregroundStyle((scheme == .dark ? Color.white : Color.black).opacity(0.6))
                }
                .frame(maxWidth: 260)
                .padding(.bottom, 60)
            }
        }
        .task {
            // One line at a time: fade in, hold, fade fully out, then swap the text. Lines never overlap.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.5)) { lineOpacity = 1 }
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeInOut(duration: 0.5)) { lineOpacity = 0 }
                try? await Task.sleep(for: .seconds(0.55))
                lineIndex = (lineIndex + 1) % lines.count
            }
        }
    }
}

/// Original movie-night jokes for the start-up screen (a different order every launch).
enum LaunchLines {
    static let all = [
        "Warming up the popcorn…",
        "Rewinding tapes nobody rewinds anymore…",
        "Looking for the remote. It's in the couch. It's always in the couch.",
        "Skipping the previews you'd skip anyway…",
        "Asking the sequel nicely to be good…",
        "Making sure the hero survives until the credits…",
        "Pretending the plot makes sense…",
        "Hiding the spoilers where you can't find them…",
        "Dimming the lights. Silencing the phones. Mostly.",
        "Checking if there's a post-credits scene. There's always a post-credits scene.",
        "Arguing about what to watch. Again.",
        "Loading the plot twist. Don't peek.",
        "Convincing the dog to stop barking at the TV…",
        "Setting the volume to \"just right\" after the loud part…",
        "Finding the one scene everyone quotes…",
        "Practicing a dramatic slow-motion walk…",
        "Cleaning up the couch crumbs from last movie night…",
        "Reminding the villain it's his turn to monologue…",
        "Counting how many times the car explodes…",
        "Trading a cliffhanger for a snack break…",
        "Teaching the hero to dodge bullets. Mostly.",
        "Rehearsing the \"I'm getting too old for this\" speech…",
        "Waiting for the car to start. In horror movies it never does.",
        "Letting the dramatic pause last a little too long…",
        "Checking the basement. Nobody should ever check the basement.",
        "Polishing the trophy nobody remembers to thank us for…",
        "Recasting the lead. Again. Casting is hard.",
        "Building a trailer that spoils the whole movie…",
        "Fact-checking the \"based on a true story\" part…",
        "Turning the subtitles on because the whistling is too loud…",
        "Adding a training montage. Everything improves with a training montage.",
        "Sharpening the one-liner for right after the explosion…",
        "Looking for a sequel nobody asked for…",
        "Reshooting the ending nobody liked…",
        "Calming down the extras in the background…",
        "Finding where the sidekick keeps getting lost…",
        "Pausing for the romantic rain scene…",
        "Hiding the boom mic just out of frame…",
        "Explaining time travel. We'll get back to you.",
        "Reminding the detective he's off the case. He knows.",
        "Putting the twist where nobody will guess it…",
        "Getting the robots to stop wanting to take over…",
        "Asking the dinosaurs to please stay inside the park…",
        "Reading the fine print on \"one last job\"…",
        "Looking for the sock that vanished during the heist…",
        "Counting the heroes who walk away from an explosion without looking…",
        "Delivering the plot hole to the plot hole department…",
        "Spinning the globe to pick a filming location…",
        "Making sure the ship doesn't hit anything this time…",
        "Waiting for someone to say \"we need to talk\"…",
        "Gathering the team for one last mission. Again.",
        "Pulling the one string that unravels everything…",
        "Teaching the wizard to use a phone…",
        "Choosing between the red pill and a snack…",
        "Sneaking past the guard who always looks the other way…",
        "Reminding the monster that the lights are off for a reason…",
        "Finding a hat that makes the hero look rugged…",
        "Asking the villain to speak up. We missed the plan.",
        "Drawing a treasure map with a suspiciously large X…",
        "Taking the long way around, because that's the scenic route in every road movie…",
        "Gluing the cowboy hat back on the cowboy…",
        "Waiting for the slow clap to build…",
        "Loading the montage music. You know the song.",
        "Setting the stage for a dramatic staircase fall…",
        "Warming up the \"NOOOOO\" in slow motion…",
        "Teaching the spaceship to stop making noise in space…",
        "Finding the one parking spot that's always open in movies…",
        "Arguing with the GPS in the getaway car…",
        "Rewriting the script on a napkin. It's the best draft yet.",
        "Looking for the chosen one. Check under the couch.",
        "Rolling the credits. Just kidding, we just started.",
        "Setting up the fake mustache for the undercover scene…",
        "Confirming the hacker really does type that fast…",
        "Making the cliffhanger a little hangier…",
        "Persuading the hero to take a day off…",
        "Cutting the scene where everyone just sat there…",
        "Checking that the villain's lair has a snack bar…",
        "Waiting for the grumpy mentor to say \"again\"…",
        "Rolling for initiative on movie night…",
        "Hiring a stunt double for the loading bar…",
        "Locating the key that opens exactly one door…",
        "Letting the dramatic music swell. A little more. Okay, that's enough.",
        "Looking for the character who says \"I've got a bad feeling about this\"…",
        "Stalling until the cavalry arrives…",
        "Flipping a coin to decide who dies in the first ten minutes…",
        "Remembering where we left the golden ticket…",
        "Asking the sequel to please bring back the original cast…",
        "Casting a pigeon as the wise old owl…",
        "Filling the theater with the smell of buttered everything…",
        "Sending a very serious memo to the villain's henchmen…",
        "Looking for loopholes in the time loop…",
        "Practicing the line \"It was me all along\"…",
        "Adjusting the thermostat to \"mysterious fog\"…",
        "Washing the cape. It's been through a lot.",
        "Getting the band back together for one more movie…",
        "Pushing the big red button. Not that one. The other one.",
        "Trying to remember who the narrator is…",
        "Asking the hero to stop narrating everything…",
        "Making a prop out of a banana. It's convincing.",
        "Parking the flying car in a no-flying zone…",
        "Finding the exact moment the movie turned into a musical…",
        "Blowing the dust off a very old, very cursed VHS…",
        "Checking that the escape tunnel actually goes somewhere…",
        "Trimming the slow bits. All of them.",
        "Setting up the one scene where nobody has a phone signal…",
        "Filling in for the actor who \"had a scheduling conflict\"…",
        "Placing a mysterious briefcase in the middle of the table…",
        "Waiting for the lights to flicker. It's about to get spooky.",
        "Giving the penguin a speaking role…",
        "Overthinking the mid-credits scene…",
        "Sorting the movie night snacks by dramatic effect…",
        "Dubbing the dog. He had a lot to say.",
        "Looking up whether the shark is still in the water…",
        "Making the cheesy line even cheesier…",
        "Reinventing the wheel. For the chase scene.",
        "Stacking five explosions into one very big one…",
        "Telling the villain the hero has a perfect plan. He doesn't.",
        "Confirming the haunted house has Wi-Fi…",
        "Rounding up a posse of very reluctant heroes…",
        "Waiting on the sidekick, who ran to get snacks…",
        "Practicing the dramatic door kick. It was unlocked.",
        "Finishing the training montage. One more push-up…",
        "Bribing the projector to stay on for the whole movie…",
        "Pretending we weren't crying at the sad part…",
        "Finding a very small violin for the sad scene…",
        "Taking five on the red carpet…",
        "Locating the director's chair. Someone is already sitting in it.",
        "Hearing the evil laugh. Looks like we're almost there.",
        "Lights, camera, loading…",
        "Cutting to the good part…",
        "Taking a quick cut-scene break…",
        "Reel talk: this is almost done…",
        "Trying not to get too corny about it…",
        "Popping the corn. Kernel of truth coming up…",
        "A star is bored. We're working on it.",
        "Directing traffic on the data highway…",
        "This one's a real cliffhanger…",
        "Making a scene about the loading…",
        "Setting the stage. Fighting the stage fright…",
        "Rolling the credits early, just in case…",
        "Please remain seated. The show is almost on screen.",
        "Dolly zooming in on your content…",
        "Fade to black. Fade back in. Nailed it.",
        "Casting a spell on the buffering wheel…",
        "That's a wrap on the loading. Almost…",
        "Doing some shot-by-shot work behind the scenes…",
        "Calling in the stunt double for the loading bar…",
        "Prepping the montage with swelling music…",
        "Sequel-izing the loading screen. Part two coming up…",
        "No spoilers, only spoiled snacks…",
        "Giving the loading bar its big break…",
        "Setting up the green screen. Please don't wear green…",
        "Taking the long way, for dramatic effect…",
        "Staying under budget on loading time. Barely…",
        "On location, loading…",
        "Roll the footage. Roll. Roll…",
        "Waiting for the trailer to finish telling us the whole movie…",
        "It's not a delay, it's a suspenseful pause…",
        "Hang on, we're in the middle of a plot twist.",
        "This loading screen is an indie. Slow burn, big payoff.",
        "Just a few more takes…",
        "Spooling up the film. Yes, it's digital. We like the sound.",
        "Applying a little post-production polish…",
        "Standing by for the director's notes…",
        "Mixing sound, picture and snacks…",
        "Almost at the climax. Hold your breath, not the popcorn.",
        "A little drama never hurt a loading bar…",
        "Telling the loading bar it's the star of the show…",
        "Finding your best side for the close-up…",
        "Adding extras to make the crowd scene look busy…",
        "Choreographing a fight scene between two progress bars…",
        "Waiting for the cameo. There's always a cameo.",
        "Editing out the awkward silence…",
        "Loading a very large supporting cast…",
        "Hold on to your seat, it's an action-packed load…",
        "Rehearsing our speech for fastest loading screen of the year…",
        "Giving this load a standing ovation in advance…",
        "Matinee mode: now loading at a leisurely pace…",
        "Please enjoy this intermission from your regularly scheduled loading…",
        "Our loading screen is on the cutting-room floor. It'll be right back.",
        "A long take. A very long take…",
        "Tracking the shot across the data…",
        "Ripping the frames from the film. Gently…",
        "Jaw-dropping content is on its way. Mouths closed, please.",
        "It's a Wonderful Wi-Fi signal. Mostly.",
        "Somewhere over the buffering rainbow…",
        "A tale of two loading bars…",
        "The Good, the Bad and the Buffering…",
        "Gone With the Wind. Back with the data…",
        "The Wizard of Oz-ome loading screen…",
        "To Kill a Mocking Buffer…",
        "Dial M for Movies…",
        "Wait Until Dark. Then wait a little more…",
        "Kung Fu Panda-monium behind the scenes…",
        "Singin' in the Reel…",
        "Finding Memo. Found the memo. Lost the memo again…",
        "Alien-ating the buffering gremlins…",
        "The Lion King of Loading screens…",
        "Gladiator Games? No, load-iator games…",
        "Toy Story-telling at 24 frames a second…",
        "Gravity-defying load times. Falling slowly…",
        "Back to the Future. Please hold for the present…",
        "Raiders of the Lost Cache…",
        "The Dark Knight Rises. So does the loading bar.",
        "Silence of the Lambs? More like silence of the loading bars…",
        "Rocky Road to loading success. Extra nuts, hold the buffering…",
        "Inception: a load within a load within a load…",
        "Jurassic Park it right there while we fetch your content…",
        "Frozen in time. Thawing the data…",
        "Home Alone with the loading bar. It has booby traps…",
        "The Matrix is loading. There is no spoon. Or buffering.",
        "Moonlight and loading. A romantic combination.",
        "Mission: Impossible? No, mission: possible, and slightly slow.",
        "Ocean's Eleven percent loaded…",
        "The Sound of Loading. The hills are alive with data…",
        "Up, up, and away with your content…",
        "Ferris Bueller's Day Off, and so is our server for a second…",
        "Pirates of the Caribbean-dwidth…",
        "Forrest Gump-ing along at the speed of data…",
        "Planet of the Apes of the Cache…",
        "The Shawshank Redemption of your watchlist…",
        "It's alive! The server, that is…",
        "The Princess Bride-width is being upgraded…",
        "Beauty and the Buffer…",
        "The Fast and the Buffer-ious…",
        "Close Encounters of the Third Load…",
        "Finding Nemo-ry. We forgot what we were loading…",
        "Spirited Away to the data center…",
        "Hocus Pocus-ing your content into view…",
        "Superman? More like super-load, man…",
        "The Hobbit-ual delay. Second breakfast of data first…",
        "Honey, I Shrunk the Bandwidth…",
        "Titanic-ally large load. No icebergs found yet…",
        "The Terminator-minal loading screen. It'll be back…",
        "Back to the Buffer…",
        "Snakes on a Plane-t of data…",
        "The Grand Budapest Hotel? Grand Budget Hostel of loading screens…",
        "Singing in the rain. Loading in the sun…",
        "Whiplash? No, whip-load, quickly…",
        "Interstellar travel at the speed of Wi-Fi…",
        "Shrek-ing the cache. It's got layers…",
        "Cars? More like cache, vroom vroom…",
        "Coco-nut loading in progress…",
        "Frozen yogurt for the loading wait. It's thawing…",
        "Remember the Titan-ic-ally fast load. Remember it…",
        "The Sixth Load. We see dead pixels…",
        "Little Miss Sunshine and Rainbows of Bandwidth…",
        "How to Train Your Dragon-ging Load…",
        "Lost in Translation, found in loading…",
        "The Princess Diaries of a buffering icon…",
        "Rear Window of opportunity. Opening shortly…",
        "Some Like It Hot. Some like it cached…",
        "The Social Network? It's the local network that needs a moment…",
        "Doctor Strangeload. Or How I Learned to Stop Worrying and Love the Spinner…",
        "A Fistful of Dollars? No, a fistful of data…",
        "The Great Escape from the loading screen. We're tunnelling now…",
        "Jaws. We're going to need a bigger buffer…",
        "The Godfather of all loading screens. We made it an offer it can't refuse…",
        "Mad Max: Fury Road to loading…",
        "Sleepless in Seattle. Also sleepless in San Antonio…",
        "Good Will Loading…",
        "Back to the Future of your movie night…",
        "There Will Be Loading. There will be popcorn…",
        "The Fellowship of the Ping…",
        "Cast Away on a desert island with only a progress bar…",
        "Bridge of Spies on your internet connection…",
        "A Beautiful Mind-ful load…",
        "Dunkirk? Dunk-it-in. Dunking the data…",
        "A Quiet Place to wait. Please shhh…",
        "The Princess Bride is okay. Really. Also loading…",
        "The Truman Show: you are in the movie of loading…",
        "Groundhog Day: loading again. And again. And again…",
        "Casablanca: we'll always have the loading screen…",
        "It's a Mad, Mad, Mad, Mad World. Of loading…",
        "Edward Scissorhands off the buffering wheel…",
        "Toy Story-time is over. Load time too, almost…",
        "Finding Dory-ven data. Wait, what were we doing?",
        "Frozen II: Electric Boogaloo, the loading screen…",
        "Asking the getaway driver to stand in the right light…",
        "Asking the wizard to lower the dramatic music…",
        "Asking the butler to stop looking at the camera…",
        "Asking the cowboy to stay dead this time…",
        "Asking the stunt double to stop leaving cryptic notes…",
        "Asking the talking dog to stop leaving cryptic notes…",
        "Asking the stunt double to stop bringing a sword to a gunfight…",
        "Asking the narrator to stop bringing a sword to a gunfight…",
        "Asking the vampire to say the line with feeling…",
        "Asking the hero to stop leaving cryptic notes…",
        "Asking the robot to stay out of the basement…",
        "Asking the intern to return the borrowed time machine…",
        "Asking the detective to act surprised…",
        "Asking the superhero to leave the third act alone…",
        "Asking the pirate to stand in the right light…",
        "Asking the ghost to stop bringing a sword to a gunfight…",
        "Asking the butler to stay dead this time…",
        "Asking the stunt double to hold the dramatic pause…",
        "Asking the mad scientist to stay dead this time…",
        "Asking the mad scientist to hold the dramatic pause…",
        "Asking the cat burglar to stop walking away from explosions…",
        "Asking the wizard to stop walking away from explosions…",
        "Asking the sidekick to lower the dramatic music…",
        "Asking the ghost to stop looking at the camera…",
        "Asking the spy to stay dead this time…",
        "Asking the film critic to wait for the credits…",
        "Asking the talking dog to check the plot for holes…",
        "Asking the ninja to stop adding a cameo…",
        "Asking the hero to take the stairs…",
        "Asking the intern to use the door for once…",
        "Asking the robot to stop stealing the scene…",
        "Asking the time traveler to stop monologuing…",
        "Asking the vampire to stand in the right light…",
        "Asking the cowboy to stay out of the basement…",
        "Asking the cowboy to stop looking at the camera…",
        "Asking the spy to leave the third act alone…",
        "Asking the alien to stop bringing a sword to a gunfight…",
        "Asking the film critic to stop stealing the scene…",
        "Asking the alien to turn their phone off…",
        "Asking the getaway driver to stay out of the basement…",
        "Asking the getaway driver to finish their snack before the big scene…",
        "Asking the alien to say the line with feeling…",
        "Asking the getaway driver to leave the third act alone…",
        "Asking the spy to cut the slow-motion…",
        "Asking the detective to leave the third act alone…",
        "Asking the zombie to stop leaving cryptic notes…",
        "Asking the director to hold the dramatic pause…",
        "Asking the director to stay dead this time…",
        "Asking the stunt double to use the door for once…",
        "Asking the robot to check the plot for holes…",
        "Asking the director to read the script first…",
        "Asking the wizard to return the borrowed time machine…",
        "Asking the mad scientist to stand in the right light…",
        "Asking the dragon to stand in the right light…",
        "Asking the mime to stop bringing a sword to a gunfight…",
        "Asking the detective to say the line with feeling…",
        "Asking the cowboy to stand in the right light…",
        "Asking the lifeguard to turn their phone off…",
        "Asking the superhero to hold the dramatic pause…",
        "Asking the dragon to remember the safe word…",
        "Asking the villain to stop monologuing…",
        "Asking the getaway driver to hit their mark…",
        "Asking the cat burglar to keep the secret until the sequel…",
        "Asking the dragon to use the door for once…",
        "Asking the stunt double to stay out of the basement…",
        "Asking the alien to please skip the dream sequence…",
        "Asking the director to stop looking at the camera…",
        "Asking the ghost to stop adding a cameo…",
        "Asking the director to stay out of the basement…",
        "Asking the mime to stay dead this time…",
        "Asking the alien to leave the third act alone…",
        "Asking the superhero to keep the secret until the sequel…",
        "Asking the cowboy to please skip the dream sequence…",
        "Asking the film critic to stay dead this time…",
        "Asking the sidekick to check the plot for holes…",
        "Asking the vampire to stop bringing a sword to a gunfight…",
        "Asking the stunt double to return the borrowed time machine…",
        "Asking the lighting crew to stop looking at the camera…",
        "Asking the alien to return the borrowed time machine…",
        "Asking the vampire to stop walking away from explosions…",
        "Asking the mad scientist to lower the dramatic music…",
        "Asking the pirate to cut the slow-motion…",
        "Asking the butler to please skip the dream sequence…",
        "Asking the butler to hold the dramatic pause…",
        "Asking the dragon to stop adding a cameo…",
        "Asking the lifeguard to stay out of the basement…",
        "Asking the villain to hit their mark…",
        "Asking the intern to keep the secret until the sequel…",
        "Asking the ninja to stand in the right light…",
        "Asking the ghost to keep the secret until the sequel…",
        "Asking the detective to keep the secret until the sequel…",
        "Asking the robot to return the borrowed time machine…",
        "Asking the zombie to stay dead this time…",
        "Asking the butler to put the plot twist back…",
        "Asking the getaway driver to use the door for once…",
        "Asking the butler to return the borrowed time machine…",
        "Asking the cat burglar to put the plot twist back…",
        "Asking the vampire to take the stairs…",
        "Asking the pirate to turn their phone off…",
        "Asking the superhero to stop monologuing…",
        "Asking the getaway driver to turn their phone off…",
        "Asking the director to check the plot for holes…",
        "Asking the pirate to leave the third act alone…",
        "Asking the superhero to remember the safe word…",
        "Asking the spy to keep the secret until the sequel…",
        "Asking the ghost to say the line with feeling…",
        "Asking the stunt double to stop walking away from explosions…",
        "Sorting the soundtrack…",
        "Weighing the boom mic…",
        "Inflating the thunderstorm effect…",
        "Untangling the final act…",
        "Sweeping up the director's chair…",
        "Dusting off the slow-motion walk…",
        "Color-coding the slow-motion walk…",
        "Inflating the smoke machine…",
        "Inflating the cliffhanger…",
        "Calming down the director's chair…",
        "Fact-checking the thunderstorm effect…",
        "Dusting off the montage music…",
        "Hiding the clapperboard…",
        "Tuning the villain's secret lair…",
        "Alphabetizing the opening scene…",
        "Polishing the slow-motion walk…",
        "Sharpening the chase scene…",
        "Dusting off the dramatic pause…",
        "Reheating the final act…",
        "Stretching the villain's secret lair…",
        "Hiding the opening scene…",
        "Recalibrating the chase scene…",
        "Stretching the red carpet…",
        "Ironing out the plot twist…",
        "Stretching the final act…",
        "Sorting the slow-motion walk…",
        "Reheating the plot armor…",
        "Negotiating with the clapperboard…",
        "Color-coding the explosion budget…",
        "Feeding the credits…",
        "Fluffing the green screen…",
        "Reasoning with the plot armor…",
        "Fluffing the popcorn machine…",
        "Recalibrating the green screen…",
        "Bubble-wrapping the director's chair…",
        "Sweeping up the dramatic rain…",
        "Reasoning with the opening scene…",
        "Rehearsing the stunt double…",
        "Re-shooting the movie trailer voice…",
        "Rehearsing the plot armor…",
        "Dusting off the final act…",
        "Fact-checking the gunfight standoff…",
        "Rewinding the big reveal…",
        "Sharpening the gunfight standoff…",
        "Ironing out the movie trailer voice…",
        "Feeding the boom mic…",
        "Recalibrating the clapperboard…",
        "Weighing the thunderstorm effect…",
        "Reasoning with the credits…",
        "Recalibrating the red carpet…",
        "Rehearsing the popcorn machine…",
        "Dusting off the green screen…",
        "Sorting the thunderstorm effect…",
        "Rewinding the final act…",
        "Fluffing the thunderstorm effect…",
        "Feeding the car chase…",
        "Rehearsing the dramatic pause…",
        "Stretching the explosion budget…",
        "Reasoning with the soundtrack…",
        "Dusting off the training montage…",
        "Rewinding the sequel…",
        "Waking up the cliffhanger…",
        "Rewinding the thunderstorm effect…",
        "Hiding the popcorn machine…",
        "Bubble-wrapping the dramatic pause…",
        "Rehearsing the red carpet…",
        "Hiding the sequel…",
        "Polishing the explosion budget…",
        "Inflating the montage music…",
        "Polishing the final act…",
        "Reheating the popcorn machine…",
        "Fluffing the cliffhanger…",
        "Reheating the intermission…",
        "Recalibrating the sequel…",
        "Negotiating with the dramatic pause…",
        "Reheating the training montage…",
        "Reasoning with the popcorn machine…",
        "Rehearsing the explosion budget…",
        "Color-coding the final act…",
        "Reasoning with the thunderstorm effect…",
        "Waking up the clapperboard…",
        "Alphabetizing the villain's secret lair…",
        "Untangling the green screen…",
        "Warming up the sequel…",
        "Negotiating with the explosion budget…",
        "Tuning the car chase…",
        "Sorting the dramatic rain…",
        "Weighing the dramatic rain…",
        "Bubble-wrapping the movie trailer voice…",
        "Stretching the extras…",
        "Calming down the movie trailer voice…",
        "Sweeping up the opening scene…",
        "Sorting the plot armor…",
        "Bubble-wrapping the boom mic…",
        "Reheating the dramatic rain…",
        "Color-coding the credits…",
        "Dusting off the sequel…",
        "Sharpening the green screen…",
        "Tuning the movie trailer voice…",
        "Sharpening the thunderstorm effect…",
        "Ironing out the training montage…",
        "Waking up the big reveal…",
        "Warming up the clapperboard…",
        "Sharpening the sequel…",
        "Tuning the extras…",
        "Feeding the green screen…",
        "Inflating the slow-motion walk…",
        "Color-coding the stunt double…",
        "Reasoning with the gunfight standoff…",
        "Fact-checking the slow-motion walk…",
        "Waiting for the dragon to turn around slowly…",
        "Waiting for the music to come back from commercial…",
        "Waiting for the intermission to turn around slowly…",
        "Waiting for the film crew to remember its lines…",
        "Waiting for the music to stop being dramatic…",
        "Waiting for the plot to take a bow…",
        "Waiting for the third act to stop being dramatic…",
        "Waiting for the trailer to get out of the shot…",
        "Waiting for the film crew to stop looking at the camera…",
        "Waiting for the director to say something clever…",
        "Waiting for the monster to hit the high note…",
        "Waiting for the rain machine to stop being dramatic…",
        "Waiting for the spy to stop pointing at the sky…",
        "Waiting for the film crew to find its mark…",
        "Waiting for the car chase to change the subject…",
        "Waiting for the stunt team to hit the high note…",
        "Waiting for the final boss to change the subject…",
        "Waiting for the film crew to get out of the shot…",
        "Waiting for the lead actor to find the exit…",
        "Waiting for the plot to come back from commercial…",
        "Waiting for the pizza guy to come back from commercial…",
        "Waiting for the spy to remember its lines…",
        "Waiting for the car chase to catch the bus…",
        "Waiting for the plot to say something clever…",
        "Waiting for the monster to catch the bus…",
        "Waiting for the spy to wake up…",
        "Waiting for the getaway van to hit the high note…",
        "Waiting for the car chase to say something clever…",
        "Waiting for the train to take a bow…",
        "Waiting for the explosion to stop pointing at the sky…",
        "Waiting for the car chase to remember its lines…",
        "Waiting for the villain to change the subject…",
        "Waiting for the third act to finish the dramatic walk…",
        "Waiting for the pizza guy to hit the high note…",
        "Waiting for the spy to put on its hat…",
        "Waiting for the pizza guy to stop pointing at the sky…",
        "Waiting for the sequel to say something clever…",
        "Waiting for the lead actor to stop looking at the camera…",
        "Waiting for the explosion to finish its coffee…",
        "Waiting for the stunt team to stop pointing at the sky…",
        "Waiting for the train to come back from commercial…",
        "Waiting for the sequel to find its mark…",
        "Waiting for the rain machine to finish the dramatic walk…",
        "Waiting for the villain to stop pointing at the sky…",
        "Waiting for the car chase to get out of the shot…",
        "Waiting for the sequel to finish its coffee…",
        "Waiting for the lead actor to put on its hat…",
        "Waiting for the intermission to find the exit…",
        "Waiting for the director to stop pointing at the sky…",
        "Waiting for the rain machine to stop looking at the camera…",
        "Waiting for the rain machine to find the exit…",
        "Waiting for the monster to get out of the shot…",
        "Waiting for the spy to come back from commercial…",
        "Waiting for the intermission to get out of the shot…",
        "Waiting for the lead actor to say something clever…",
        "Waiting for the villain to put on its hat…",
        "Waiting for the dancing extras to remember its lines…",
        "Waiting for the stunt team to wake up…",
        "Waiting for the getaway van to finish the dramatic walk…",
        "Waiting for the dancing extras to turn around slowly…",
        "Waiting for the monster to finish its coffee…",
        "Waiting for the rain machine to remember its lines…",
        "Waiting for the trailer to put the script down…",
        "Waiting for the monster to take a bow…",
        "Waiting for the train to turn around slowly…",
        "Waiting for the dancing extras to put on its hat…",
        "Waiting for the car chase to come back from commercial…",
        "Waiting for the pizza guy to put the script down…",
        "Waiting for the music to find its mark…",
        "Waiting for the villain to finish the dramatic walk…",
        "Waiting for the monster to wake up…",
        "Waiting for the trailer to finish the dramatic walk…",
        "Waiting for the hero's flashback to wrap up the scene…",
        "Waiting for the villain to wake up…",
        "Waiting for the hero's flashback to turn around slowly…",
        "Waiting for the car chase to finish the dramatic walk…",
        "Waiting for the train to finish its coffee…",
        "Waiting for the train to remember its lines…",
        "Waiting for the music to put the script down…",
        "Waiting for the rain machine to turn around slowly…",
        "Loading 12 cliffhangers. Estimated time: the length of a trailer.",
        "Loading 1000 film reels. Estimated time: two sequels.",
        "Loading 60 film reels. Estimated time: half a director's cut.",
        "Loading 120 extras. Estimated time: a coffee refill.",
        "Loading 400 one-liners. Estimated time: a dramatic pause.",
        "Loading 60 dream sequences. Estimated time: one montage.",
        "Loading 800 extras. Estimated time: a bathroom break.",
        "Loading 120 trailers. Estimated time: one dramatic sigh.",
        "Loading 60 unhelpful sidekicks. Estimated time: one popcorn refill.",
        "Loading 40 cliffhangers. Estimated time: a coffee refill.",
        "Loading 88 plot twists. Estimated time: a bathroom break.",
        "Loading 88 explosions. Estimated time: a theatrical release window.",
        "Loading 400 dream sequences. Estimated time: half a director's cut.",
        "Loading 2000 film reels. Estimated time: half a director's cut.",
        "Loading 40 plot twists. Estimated time: a dramatic pause.",
        "Loading 1000 trailers. Estimated time: a bathroom break.",
        "Loading 1200 soundtrack violins. Estimated time: a theatrical release window.",
        "Loading 200 one-liners. Estimated time: one lunch break.",
        "Loading 120 cliffhangers. Estimated time: a dramatic pause.",
        "Loading 40 one-liners. Estimated time: one montage.",
        "Loading 5000 extras. Estimated time: a dramatic pause.",
        "Loading 120 film reels. Estimated time: one lunch break.",
        "Loading 10000 tiny umbrellas for the rain scene. Estimated time: a coffee refill.",
        "Loading 250 tiny popcorn kernels. Estimated time: one popcorn refill.",
        "Loading 1200 plot twists. Estimated time: a coffee refill.",
        "Loading 40 film reels. Estimated time: a theatrical release window.",
        "Loading 200 slow-motion walks. Estimated time: one intermission.",
        "Loading 500 one-liners. Estimated time: three plot twists.",
        "Loading 12 slow-motion walks. Estimated time: one slow-motion walk.",
        "Loading 120 soundtrack violins. Estimated time: three plot twists.",
        "Loading 5000 candy wrappers. Estimated time: half a director's cut.",
        "Loading 800 stunt doubles. Estimated time: a very long take.",
        "Loading 640 slow-motion walks. Estimated time: a very long take.",
        "Loading 60 tiny umbrellas for the rain scene. Estimated time: half a director's cut.",
        "Loading 800 unhelpful sidekicks. Estimated time: a dramatic pause.",
        "Loading 12 tiny umbrellas for the rain scene. Estimated time: two sequels.",
        "Loading 2000 dream sequences. Estimated time: a very long take.",
        "Loading 640 candy wrappers. Estimated time: a dramatic pause.",
        "Loading 120 movie posters. Estimated time: a very long take.",
        "Loading 12 unhelpful sidekicks. Estimated time: one dramatic sigh.",
        "Loading 5000 tiny popcorn kernels. Estimated time: a bathroom break.",
        "Loading 2000 film reels. Estimated time: a bathroom break.",
        "Loading 1200 slow-motion walks. Estimated time: one popcorn refill.",
        "Loading 120 soundtrack violins. Estimated time: one montage.",
        "Loading 500 dream sequences. Estimated time: half a director's cut.",
        "Loading 60 post-credits scenes. Estimated time: half a director's cut.",
        "Loading 88 unhelpful sidekicks. Estimated time: one lunch break.",
        "Loading 12 film reels. Estimated time: a theatrical release window.",
        "Loading 40 soundtrack violins. Estimated time: a theatrical release window.",
        "Loading 10000 candy wrappers. Estimated time: one slow-motion walk.",
        "Loading 88 soundtrack violins. Estimated time: the length of a trailer.",
        "Loading 1200 stunt doubles. Estimated time: two sequels.",
        "Loading 400 slow-motion walks. Estimated time: half a director's cut.",
    ]
    static func shuffled() -> [String] { all.shuffled() }
}

/// Gets the app ready during the start-up screen: addons, libraries, home rows, card artwork,
/// and the poster images themselves (so they're already in the image cache when you open Dashboard).
@MainActor
final class Preloader: ObservableObject {
    /// The start-up screen always stays up at least this long.
    static let minimumSeconds = 4.0

    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Starting…"
    @Published private(set) var done = false
    /// True while a pull-down refresh is running: the same screen comes back with just "Refreshing…" under the bar.
    @Published private(set) var refreshing = false

    /// Handed to BrowseView so it has something to show immediately.
    private(set) var homeRows: [CatalogRow] = []
    private(set) var art: [BrowseCategory.Kind: [URL]] = [:]

    private func set(_ p: Double, _ s: String) {
        progress = max(progress, min(p, 1))
        status = refreshing ? "Refreshing…" : s
    }

    func run(store: AddonStore, trakt: TraktAuth, services: Services,
             account: NuviAccount, progress: ProgressStore) async {
        guard !done else { return }
        let started = Date()

        // Never keep someone waiting more than 20 seconds, whatever the network is doing.
        let work = Task { await self.prepare(store: store, trakt: trakt, services: services, account: account, progress: progress) }
        let guardTask = Task { try? await Task.sleep(for: .seconds(20)); work.cancel() }
        await work.value
        guardTask.cancel()

        set(1, "Done!")
        // Keep the start-up screen up for at least four seconds, even when everything loaded fast.
        let shown = Date().timeIntervalSince(started)
        if shown < Self.minimumSeconds { try? await Task.sleep(for: .seconds(Self.minimumSeconds - shown)) }
        withAnimation(.easeOut(duration: 0.35)) { done = true }
    }

    /// Pull-down refresh: reloads everything behind the loading screen. Start-up is unchanged.
    func refresh(store: AddonStore, trakt: TraktAuth, services: Services,
                 account: NuviAccount, progress: ProgressStore) async {
        guard done, !refreshing else { return }
        let started = Date()
        self.progress = 0
        refreshing = true
        status = "Refreshing…"
        let work = Task { await self.prepare(store: store, trakt: trakt, services: services, account: account, progress: progress) }
        let guardTask = Task { try? await Task.sleep(for: .seconds(20)); work.cancel() }
        await work.value
        guardTask.cancel()
        set(1, "Refreshing…")
        let shown = Date().timeIntervalSince(started)
        if shown < Self.minimumSeconds { try? await Task.sleep(for: .seconds(Self.minimumSeconds - shown)) }
        refreshing = false
    }

    private func prepare(store: AddonStore, trakt: TraktAuth, services: Services,
                         account: NuviAccount, progress: ProgressStore) async {
        if account.isSignedIn {
            set(0.02, "Syncing your account…")
            await account.sync(store: store, progress: progress, force: true)
        }
        set(0.05, "Loading your addons…")
        async let addons: Void = store.load()
        async let libraries: Void = services.refreshLibraries()
        _ = await (addons, libraries)
        if Task.isCancelled { return }

        set(0.30, "Getting your catalogs…")
        async let rows = HomeRows.load(store.addons)
        async let covers = CoverArt.load(addons: store.addons, trakt: trakt, services: services)
        homeRows = await rows
        art = await covers
        if Task.isCancelled { return }

        // Everything else worth having ready: every catalog, ratings, title details, stream links, then all the pictures.
        set(0.38, "Loading every catalog…")
        var titles = await Warmup.catalogs(store.addons)
        if trakt.isSignedIn { titles += await WatchlistLoader.load(trakt.watchlist, addons: store.addons) }
        titles += homeRows.flatMap(\.items)
        var seenIDs = Set<String>()
        titles = titles.filter { seenIDs.insert($0.type + $0.id).inserted }
        ContentFilter.shared.note(titles)
        if Task.isCancelled { return }

        set(0.50, "Checking ratings…")
        await ContentFilter.shared.classifyNow(titles.map(\.id))
        await Warmup.ratings(Array(titles.prefix(80)))
        Ratings.persist()
        if Task.isCancelled { return }

        set(0.62, "Getting details…")
        let details = await Warmup.details(Array(titles.prefix(40)), addons: store.addons)
        if Task.isCancelled { return }

        set(0.72, "Finding links…")
        await Warmup.streams(Array(titles.filter { $0.type == "movie" }.prefix(10)), addons: store.addons)
        if Task.isCancelled { return }

        var urls: [URL] = art.values.flatMap { $0 }.map(CoverArt.hiRes)
        urls += (titles + details).flatMap { [$0.poster, $0.background] }.compactMap { $0.flatMap(URL.init(string:)) }
        let logos = await services.tmdb.providerLogos()
        urls += StreamingService.all.compactMap { logos[$0.provider] }   // service logos for the Search tab
        var seen = Set<URL>()
        urls = urls.filter { seen.insert($0).inserted }.prefix(500).map { $0 }

        set(0.78, "Caching covers…")
        await prefetch(urls)
    }

    /// Downloads images into the shared URLCache, a few at a time, moving the bar as they land.
    private func prefetch(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        var finished = 0
        await withTaskGroup(of: Void.self) { group in
            var iterator = urls.makeIterator()
            func next(_ g: inout TaskGroup<Void>) {
                guard let url = iterator.next() else { return }
                g.addTask {
                    var req = URLRequest(url: url)
                    req.cachePolicy = .returnCacheDataElseLoad
                    req.timeoutInterval = 10
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
            for _ in 0..<8 { next(&group) }
            while await group.next() != nil {
                finished += 1
                set(0.78 + 0.21 * Double(finished) / Double(urls.count), "Caching covers…")
                if Task.isCancelled { group.cancelAll(); return }
                next(&group)
            }
        }
    }
}
