// Keyboard and game controllers, polled once per frame. Lua asks by name:
// keys by SDL name ("left", "return", "escape", "f12", "a"...), pad buttons
// as "pad_a", "pad_b", "pad_start", "pad_up"... (any connected pad).
#pragma once
#include <SDL.h>

#include <string>
#include <unordered_map>
#include <vector>

class Input {
public:
    void beginFrame();
    void handle(const SDL_Event& e);

    bool down(const std::string& name) const;
    bool pressed(const std::string& name) const;
    bool any() const { return anyPressed_; }
    // Name of the last key pressed this frame ("" if none).
    const std::string& last() const { return last_; }

private:
    static std::string keyName(SDL_Keycode k);
    std::unordered_map<std::string, bool> down_;
    std::unordered_map<std::string, bool> pressed_;
    bool anyPressed_ = false;
    std::string last_;
    std::vector<SDL_GameController*> pads_;
};
