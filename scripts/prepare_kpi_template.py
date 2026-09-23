"""Extract reusable layouts; never bundle historical transactions or external links.
Usage: python3 scripts/prepare_kpi_template.py SOURCE.xlsx [OUTPUT.xlsx]
"""
import sys, zipfile, re, xml.etree.ElementTree as E
src=sys.argv[1]
out=sys.argv[2] if len(sys.argv)>2 else 'assets/export_templates/kpi-2026-layout.xlsx'
ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
E.register_namespace('',ns)
E.register_namespace('r','http://schemas.openxmlformats.org/officeDocument/2006/relationships')
with zipfile.ZipFile(src) as z, zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as dst:
 ss=[''.join(t.itertext()) for t in E.fromstring(z.read('xl/sharedStrings.xml'))]
 for i in range(1,20):
  path=f'xl/worksheets/sheet{i}.xml'; r=E.fromstring(z.read(path))
  for c in r.iter('{'+ns+'}c'):
   ref=c.get('r'); row=int(re.search(r'\d+',ref)[0]); col=re.match('[A-Z]+',ref)[0]
   v=c.find('{'+ns+'}v'); text=ss[int(v.text)] if c.get('t')=='s' and v is not None else None
   keep=False
   if i<=9:
    keep=text in ['FUEL','Salary','Maintenance','PO No. / Ref','DATE','Amount','Liter','PRICE/LITER','Date','Ref','Description','Revenue','Total'] or (text is not None and re.fullmatch(r'(?:PM\s*\d+|week \d+)',text) is not None)
   elif i==10:
    keep=text is not None and (row<10 or col in ['A','B'])
   else:
    label='B' if i<=12 else 'C';unit='A' if i<=12 else 'B'
    keep=text is not None and (row<10 or col==label or (col==unit and row in [10,20,30,40]))
   for child in list(c): c.remove(child)
   for attr in ['t','cm','vm']: c.attrib.pop(attr,None)
   if keep:
    c.set('t','inlineStr'); t=E.SubElement(E.SubElement(c,'{'+ns+'}is'),'{'+ns+'}t'); t.set('{http://www.w3.org/XML/1998/namespace}space','preserve');t.text=text
  for tag in ['drawing','legacyDrawing','extLst']:
   for el in r.findall('{'+ns+'}'+tag):r.remove(el)
  dst.writestr(path,E.tostring(r,encoding='utf-8',xml_declaration=True))
 for path in ['xl/styles.xml','xl/theme/theme1.xml']:
  dst.writestr(path,z.read(path))

 # Complete, standalone workbook package for inspection in Excel as well.
 wb=E.fromstring(z.read('xl/workbook.xml'))
 for tag in ['externalReferences','definedNames']:
  for el in wb.findall('{'+ns+'}'+tag):wb.remove(el)
 dst.writestr('xl/workbook.xml',E.tostring(wb,encoding='utf-8',xml_declaration=True))
 relns='http://schemas.openxmlformats.org/package/2006/relationships'
 rels=E.fromstring(z.read('xl/_rels/workbook.xml.rels'))
 for el in list(rels):
  if el.get('Type').split('/')[-1] not in ['worksheet','styles','theme']:rels.remove(el)
 dst.writestr('xl/_rels/workbook.xml.rels',E.tostring(rels,encoding='utf-8',xml_declaration=True))
 dst.writestr('_rels/.rels','<Relationships xmlns="'+relns+'"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
 types=E.fromstring(z.read('[Content_Types].xml'))
 retained={'/xl/workbook.xml','/xl/styles.xml','/xl/theme/theme1.xml'}|{'/xl/worksheets/sheet%d.xml'%i for i in range(1,20)}
 for el in list(types):
  if el.tag.endswith('Override') and el.get('PartName') not in retained:types.remove(el)
 dst.writestr('[Content_Types].xml',E.tostring(types,encoding='utf-8',xml_declaration=True))
