#!/usr/bin/env python3
"""Check engine action IDs against the approved Windows controller profile."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BUTTONS = {9: 0, 3: 1, 28: 2, 11: 3, 14: 4, 25: 5, 0: 6,
           24: 7, 30: 8, 13: 9, 41: 10, 31: 11, 32: 12, 20: 13, 21: 14}
AXES = {47: 0, 46: 1, 45: 2, 44: 3, 29: 4, 10: 5}


class ControllerContract(unittest.TestCase):
    def test_channels_and_neutral_values(self):
        root = ET.parse(ROOT / 'assets/input_v3.xml').getroot()
        self.assertEqual(root.tag, 'Controller')
        controls = root.findall('Control')
        self.assertEqual(len(controls), 51)
        self.assertEqual({int(c.get('name')) for c in controls}, set(range(51)))
        found_buttons, found_axes = {}, {}
        for control in controls:
            action = int(control.get('name'))
            self.assertEqual(control.find('Channel').get('number'), str(action))
            self.assertEqual(control.get('initialValue'), '0.5' if action in AXES else '0')
            for binder in control:
                if binder.tag.startswith('Joystick'):
                    self.assertEqual(binder.get('deviceId'), '1')
                    self.assertEqual(binder.get('direction'), 'INCREASE')
                if binder.tag == 'JoystickButtonBinder':
                    self.assertNotIn(action, found_buttons)
                    found_buttons[action] = int(binder.get('button'))
                if binder.tag == 'JoystickAxisBinder':
                    self.assertNotIn(action, found_axes)
                    found_axes[action] = int(binder.get('axis'))
        self.assertEqual(found_buttons, BUTTONS)
        self.assertEqual(found_axes, AXES)

    def test_keyboard_and_mouse_fallback_remains(self):
        controls = {int(c.get('name')): c for c in ET.parse(ROOT / 'assets/input_v3.xml').getroot()}
        self.assertEqual(controls[9].find('KeyBinder').get('key'), '44')  # space / activate
        self.assertEqual(controls[25].find('KeyBinder').get('key'), '62')  # F5 / quicksave
        self.assertEqual(controls[10].find('MouseButtonBinder').get('button'), 'LEFT')


if __name__ == '__main__':
    unittest.main()
