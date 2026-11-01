import importlib.util, tempfile, unittest
from unittest.mock import patch
from pathlib import Path
p=Path(__file__).with_name('background_selector.py');s=importlib.util.spec_from_file_location('ambient_background_selector',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Routing(unittest.TestCase):
 def test_active_mode_routing_uses_actual_background_not_saved_screensaver(self):
  for status,category in [('none','theme'),('amiga 14651-Faster_Than_Hell','amiga'),('screensaver fx:matrix','background'),('ttfx fixed','background'),('matrix-reactive ','background'),('eye-reactive ','background'),('tunnel-reactive ','background'),('neon-city ','background'),('vector-highway ','background'),('circuit-run ','background'),('sunset-drive ','background'),('','theme')]:
   with self.subTest(status=status),patch.object(m,'capture',return_value=status):self.assertEqual(m.active_category(),category)
 def test_current_opens_selected_mode_without_applying_a_background(self):
  for category in ('theme','background','amiga'):
   with patch.object(m,'active_category',return_value=category),patch.object(m,'capture',return_value=''),patch.object(m,'run') as run:
    m.main(['current'])
    if category=='amiga':run.assert_called_once_with(m.AMBIENT,'start','amiga')
    elif category=='background':run.assert_called_once_with('omarchy-shell','-q','avillagran.ambient-selector','toggle')
    else:run.assert_not_called()
 def test_resolution_steps_keep_other_settings_and_leave_no_empty_file(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'CONFIG',Path(d)):
   conf=Path(d)/'neon-city.conf';conf.write_text('audio=1\nresolution=auto+1\n')
   self.assertEqual(m.resolution_steps('neon-city'),1)
   m.set_resolution_steps('neon-city',-2);self.assertEqual(conf.read_text(),'audio=1\nresolution=auto-2\n')
   conf.write_text('resolution=3\n');self.assertEqual(m.resolution_steps('neon-city'),0)
   m.set_resolution_steps('neon-city',0);self.assertFalse(conf.exists())
 def test_arrows_apply_at_once_and_escape_restores_the_previous_background(self):
  item={'id':'neon-city','source':'neon-city'}
  with tempfile.TemporaryDirectory() as d,patch.object(m,'CONFIG',Path(d)/'c'),patch.object(m,'CACHE',Path(d)),patch.object(m,'RESOLUTION_UNDO',Path(d)/'undo'),patch.object(m,'TARGET',Path(d)/'target'),patch.object(m,'capture',return_value='screensaver fx:matrix'),patch.object(m,'run') as run:
   m.tune(item,1,20);m.tune(item,2,40)
   self.assertEqual(run.call_args.args,(m.AMBIENT,'start','neon-city',''));self.assertEqual(m.resolution_steps('neon-city'),2);self.assertEqual(m.fps_limit('neon-city'),40)
   m.revert_tuning()
   self.assertEqual(m.resolution_steps('neon-city'),0);self.assertEqual(m.fps_limit('neon-city'),20);run.assert_called_with(m.AMBIENT,'start','screensaver','fx:matrix');self.assertFalse((Path(d)/'undo').exists())
 def test_arrows_in_screensaver_mode_never_touch_the_background(self):
  item={'id':'neon-city','source':'neon-city'}
  with tempfile.TemporaryDirectory() as d,patch.object(m,'CONFIG',Path(d)/'c'),patch.object(m,'CACHE',Path(d)),patch.object(m,'RESOLUTION_UNDO',Path(d)/'undo'),patch.object(m,'TARGET',Path(d)/'target'),patch.object(m,'capture',return_value='none'),patch.object(m,'run') as run:
   (Path(d)/'target').write_text('screensaver')
   m.tune(item,1,30);m.revert_tuning();run.assert_not_called();self.assertEqual(m.resolution_steps('neon-city'),0)
 def test_fps_limit_only_takes_offered_values_and_twenty_needs_no_line(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'CONFIG',Path(d)):
   conf=Path(d)/'neon-city.conf'
   self.assertEqual(m.fps_limit('neon-city'),20)
   m.set_fps_limit('neon-city',140);self.assertEqual(conf.read_text(),'fps=140\n');self.assertEqual(m.fps_limit('neon-city'),140)
   conf.write_text('fps=900\n');self.assertEqual(m.fps_limit('neon-city'),20)
   conf.write_text('fps=auto\n');self.assertEqual(m.fps_limit('neon-city'),20)
   m.set_fps_limit('neon-city',20);self.assertFalse(conf.exists())
 def test_the_carousel_can_ask_what_it_is_choosing_for(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'TARGET',Path(d)/'target'),patch('builtins.print') as say:
   m.main(['--picking-for']);say.assert_called_with('background')
   (Path(d)/'target').write_text('screensaver')
   m.main(['--picking-for']);say.assert_called_with('screensaver')
 def test_fps_counter_toggles_a_flag_the_scenes_watch(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'FPS_COUNTER',Path(d)/'layer'/'show-fps') as flag:
   m.toggle_fps_counter();self.assertTrue(flag.exists())
   m.toggle_fps_counter();self.assertFalse(flag.exists())
 def test_cancel_theme_keeps_background(self):
  with patch.object(m,'capture',return_value=''),patch.object(m,'run') as run:m.main(['theme']);run.assert_not_called()
 def test_every_ascii_choice_has_preview_and_uses_ambient(self):
  items=m.choices('screensaver');self.assertEqual(len({i['id'] for i in items}),len(items))
  for item in items:
   self.assertTrue(item.get('poster',item['id']+'.jpg').endswith('.jpg'))
   with patch.object(m,'run') as run:
    m.main(['--apply-ascii',item['id']]);run.assert_called_once_with(m.AMBIENT,'start',item['source'],item['choice'])
 def test_the_same_carousel_picks_the_screensaver(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'TARGET',Path(d)/'target'),patch.object(m,'CACHE',Path(d)),patch.object(m,'run') as run:
   m.main(['screensaver']);run.assert_called_once_with('omarchy-shell','-q','avillagran.ambient-selector','toggle');run.reset_mock()
   m.main(['--apply-ascii','bars']);run.assert_called_once_with(m.AMBIENT,'screensaver','--set','screensaver','fx:bars');run.reset_mock()
   m.main(['--apply-ascii','neon-city']);run.assert_called_once_with(m.AMBIENT,'start','neon-city','')
   Path(d,'target').write_text('screensaver');run.reset_mock()
   m.main(['background']);m.main(['--apply-ascii','neon-city']);self.assertEqual(run.call_args.args[:3],(m.AMBIENT,'start','neon-city'))
 def test_saver_stays_as_an_alias(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'TARGET',Path(d)/'target'),patch.object(m,'CACHE',Path(d)),patch.object(m,'run'):
   m.main(['saver']);self.assertTrue(m.for_screensaver())
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
