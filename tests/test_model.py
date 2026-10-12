import unittest
from datetime import date
from model import normalize, fingerprint, day_of

class ModelTests(unittest.TestCase):
    def row(self):
        return {'timestamp':'2026-10-10T23:30:00Z','timezone':'Europe/Paris','temperature':18}
    def test_local_date(self):
        self.assertEqual(day_of(self.row()),date(2026,10,11))
    def test_naive_local(self):
        self.assertEqual(day_of({'timestamp':'10-10-2026 23:00:00'}),date(2026,10,10))
    def test_context(self):
        rows=normalize('contextualized',{'date':'2026-10-11','environmental':[self.row()],'biological':{'date':'2026-10-11'}})
        self.assertEqual(len(rows),2)
        self.assertEqual(rows[0][0],'context_environment')
    def test_inconsistent_context_rejected(self):
        with self.assertRaises(ValueError):
            normalize('contextualized',{'date':'2026-10-10','environmental':[self.row()],'biological':{'date':'2026-10-10'}})
    def test_invalid_row_rejects_document(self):
        with self.assertRaises(ValueError): normalize('computed',[self.row(),{}])
    def test_hash_stable(self):
        self.assertEqual(fingerprint({'a':1,'b':2}),fingerprint({'b':2,'a':1}))
        self.assertNotEqual(fingerprint({'a':1}),fingerprint({'a':2}))
    def test_empty_rejected(self):
        with self.assertRaises(ValueError): normalize('computed',[])
    def test_aware_requires_timezone(self):
        with self.assertRaises(KeyError): day_of({'timestamp':'2026-10-10T00:00:00Z'})

if __name__=='__main__': unittest.main()
