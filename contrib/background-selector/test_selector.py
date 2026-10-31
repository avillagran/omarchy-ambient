import importlib.util, unittest
from unittest.mock import patch
from pathlib import Path
p=Path(__file__).with_name('background_selector.py');s=importlib.util.spec_from_file_location('ambient_background_selector',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Routing(unittest.TestCase):
 def test_active_mode_routing_uses_actual_background_not_saved_screensaver(self):
  for status,category in [('none','theme'),('amiga 14651-Faster_Than_Hell','amiga'),('screensaver fx:matrix','screensaver'),('ttfx fixed','screensaver'),('matrix-reactive ','screensaver'),('eye-reactive ','screensaver'),('tunnel-reactive ','screensaver'),('neon-city ','screensaver'),('vector-highway ','screensaver'),('circuit-run ','screensaver'),('sunset-drive ','screensaver'),('','theme')]:
   with self.subTest(status=status),patch.object(m,'capture',return_value=status):self.assertEqual(m.active_category(),category)
 def test_current_opens_selected_mode_without_applying_a_background(self):
  for category in ('theme','screensaver','amiga'):
   with patch.object(m,'active_category',return_value=category),patch.object(m,'capture',return_value=''),patch.object(m,'run') as run:
    m.main(['current'])
    if category=='amiga':run.assert_called_once_with(m.AMBIENT,'start','amiga')
    elif category=='screensaver':run.assert_called_once_with('omarchy-shell','-q','avillagran.ambient-selector','toggle')
    else:run.assert_not_called()
 def test_cancel_theme_keeps_background(self):
  with patch.object(m,'capture',return_value=''),patch.object(m,'run') as run:m.main(['theme']);run.assert_not_called()
 def test_every_ascii_choice_has_preview_and_uses_ambient(self):
  items=m.choices('screensaver');self.assertEqual(len({i['id'] for i in items}),len(items))
  for item in items:
   self.assertTrue(item.get('poster',item['id']+'.jpg').endswith('.jpg'))
   with patch.object(m,'run') as run:
    m.main(['--apply-ascii',item['id']]);run.assert_called_once_with(m.AMBIENT,'start',item['source'],item['choice'])
 def test_unknown_picker_result_does_not_start(self):
  with patch.object(m,'run') as run:
   with self.assertRaises(ValueError):m.main(['--apply-ascii','untrusted'])
   run.assert_not_called()
 def test_random_all_categories_and_no_picker(self):
  for category in ('theme','screensaver','amiga'):
   item={'id':'one','label':'One'}
   with patch.object(m,'choices',return_value=[item]),patch.object(m.random.SystemRandom,'choice',side_effect=[category,item]),patch.object(m,'capture') as capture,patch.object(m,'apply') as apply,patch.object(m.subprocess,'run'):
    m.main(['random']);apply.assert_called_once_with(category,item);capture.assert_not_called()
if __name__=='__main__':unittest.main()
