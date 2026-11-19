#include "input.h"

#include <cctype>

std::string Input::keyName(SDL_Keycode k) {
    std::string n = SDL_GetKeyName(k);
    for (auto& c : n) c = char(std::tolower(static_cast<unsigned char>(c)));
    return n;
}

void Input::beginFrame() {
    pressed_.clear();
    anyPressed_ = false;
    last_.clear();
}

static const char* padName(Uint8 b) {
    switch (b) {
        case SDL_CONTROLLER_BUTTON_A: return "pad_a";
        case SDL_CONTROLLER_BUTTON_B: return "pad_b";
        case SDL_CONTROLLER_BUTTON_X: return "pad_x";
        case SDL_CONTROLLER_BUTTON_Y: return "pad_y";
        case SDL_CONTROLLER_BUTTON_START: return "pad_start";
        case SDL_CONTROLLER_BUTTON_BACK: return "pad_back";
        case SDL_CONTROLLER_BUTTON_DPAD_UP: return "pad_up";
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return "pad_down";
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return "pad_left";
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return "pad_right";
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return "pad_l";
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return "pad_r";
        default: return nullptr;
    }
}

void Input::handle(const SDL_Event& e) {
    switch (e.type) {
        case SDL_KEYDOWN: {
            std::string n = keyName(e.key.keysym.sym);
            if (!e.key.repeat) {
                pressed_[n] = true;
                anyPressed_ = true;
                last_ = n;
            }
            down_[n] = true;
            break;
        }
        case SDL_KEYUP: down_[keyName(e.key.keysym.sym)] = false; break;
        case SDL_CONTROLLERDEVICEADDED:
            if (SDL_GameController* p = SDL_GameControllerOpen(e.cdevice.which)) pads_.push_back(p);
            break;
        case SDL_CONTROLLERBUTTONDOWN:
            if (const char* n = padName(e.cbutton.button)) {
                pressed_[n] = down_[n] = true;
                anyPressed_ = true;
                last_ = n;
            }
            break;
        case SDL_CONTROLLERBUTTONUP:
            if (const char* n = padName(e.cbutton.button)) down_[n] = false;
            break;
        default: break;
    }
}

bool Input::down(const std::string& name) const {
    auto it = down_.find(name);
    return it != down_.end() && it->second;
}

bool Input::pressed(const std::string& name) const {
    auto it = pressed_.find(name);
    return it != pressed_.end() && it->second;
}
