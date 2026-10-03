# No network firewall in the Box

The Box protects the Host from Claude in YOLO mode; it does not prevent data exfiltration: Claude can reach any host on the network. An allowlist firewall (as in Anthropic's reference devcontainer) would have to be broad and constantly maintained for Maven, Gradle, npm, Playwright and Test Container images, which contradicts the goal of a lean Image. The residual risk of Workspace contents leaking is accepted deliberately.
