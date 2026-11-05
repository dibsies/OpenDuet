#!/usr/bin/env python3
"""Exercise quarantine transactions in temporary directories. Never invokes sudo."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('vendor_test',Path(__file__).with_name('vendor-free-test.py'))
vendor=importlib.util.module_from_spec(spec);spec.loader.exec_module(vendor)
class Transactions(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name)
        self.session=self.root/'session';(self.session/'copies').mkdir(parents=True);(self.session/'quarantined').mkdir()
        self.items=[]
        for index in range(3):
            source=self.root/f'component-{index}';source.write_text(f'original {index}')
            shutil.copyfile(source,self.session/'copies'/source.name)
            self.items.append({'source':str(source),'sha256':vendor.digest(source)})
    def tearDown(self):self.temporary.cleanup()
    @staticmethod
    def move(source,target):shutil.move(source,target)
    def test_round_trip(self):
        vendor.move_items(self.items,self.session,self.move)
        self.assertTrue(all(not Path(i['source']).exists() for i in self.items))
        vendor.restore_items(self.items,self.session,self.move)
        self.assertTrue(all(vendor.digest(i['source'])==i['sha256'] for i in self.items))
    def test_mid_transaction_failure_restores_every_original(self):
        def failing(source,target):
            if source==Path(self.items[2]['source']):raise OSError('simulated move failure')
            self.move(source,target)
        with self.assertRaises(OSError):vendor.move_items(self.items,self.session,failing)
        self.assertTrue(all(vendor.digest(i['source'])==i['sha256'] for i in self.items))
        self.assertEqual(list((self.session/'quarantined').iterdir()),[])
    def test_modified_backup_prevents_any_move(self):
        (self.session/'copies'/'component-2').write_text('changed')
        with self.assertRaises(RuntimeError):vendor.move_items(self.items,self.session,self.move)
        self.assertTrue(all(Path(i['source']).exists() for i in self.items))
    def test_restore_preserves_new_installation_and_restores_other_items(self):
        vendor.move_items(self.items,self.session,self.move)
        Path(self.items[0]['source']).write_text('new installation')
        with self.assertRaises(RuntimeError):vendor.restore_items(self.items,self.session,self.move)
        self.assertEqual(Path(self.items[0]['source']).read_text(),'new installation')
        self.assertTrue((self.session/'quarantined'/'component-0').exists())
        self.assertTrue(all(Path(i['source']).exists() for i in self.items[1:]))
if __name__=='__main__':unittest.main()
