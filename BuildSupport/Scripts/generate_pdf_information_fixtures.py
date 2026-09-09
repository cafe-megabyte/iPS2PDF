#!/usr/bin/env python3
"""Regenerate synthetic PDF-information fixtures (not an app/runtime dependency).
Requires pypdf with its crypto extra, Ghostscript on PATH and the macOS sRGB profile.
Run explicitly: generation overwrites the named fixture PDFs. Encryption salts and
producer timestamps make byte-for-byte regeneration intentionally nondeterministic.
"""
from pathlib import Path
from pypdf import PdfWriter
from pypdf.generic import DictionaryObject as D, NameObject as N, ArrayObject as A, NumberObject as I, DecodedStreamObject, TextStringObject as T
r=Path(__file__).resolve().parents[2]/'Tests/Unit/Fixtures'
r.mkdir(parents=True, exist_ok=True)
def d(**kw): return D({N('/'+k):v for k,v in kw.items()})
def stream(w,content,**kw):
 s=DecodedStreamObject();s.set_data(content);s.update(d(**kw));return w._add_object(s)
def base():
 w=PdfWriter();p=w.add_blank_page(width=612,height=792)
 f=w._add_object(d(Type=N('/Font'),Subtype=N('/Type1'),BaseFont=N('/Helvetica')))
 unused=w._add_object(d(Type=N('/Font'),Subtype=N('/Type1'),BaseFont=N('/Courier')))
 p[N('/Resources')]=d(Font=d(F1=f,Unused=unused))
 p[N('/Contents')]=stream(w,b'BT /F1 18 Tf 50 700 Td (PDF information fixture) Tj ET')
 w.add_metadata({'/Title':'PDF Information Test','/Author':'iPS2PDF tests','/Custom':'Unicode: ÄÖÜ €'})
 return w,p,f
w,p,f=base();w.write(r/'InfoPlain.pdf')
for alg in ['RC4-40','RC4-128','AES-128','AES-256']:
 w,p,f=base();w.encrypt('user-test','owner-test',algorithm=alg,permissions_flag=4);w.write(r/('InfoEncrypted-'+alg+'.pdf'))
w,p,f=base();w.encrypt('','owner-test',algorithm='AES-128',permissions_flag=4);w.write(r/'InfoEmptyPassword.pdf')
w,p,f=base();w.encrypt('Päss (\\) € 🔒','Öwner 🔑',algorithm='AES-256',permissions_flag=4);w.write(r/'InfoUnicodePassword.pdf')
w,p,f=base()
xmp=b'''<?xpacket begin=""?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" pdfaid:part="2" pdfaid:conformance="B"/></rdf:RDF></x:xmpmeta><?xpacket end="w"?>'''
w._root_object[N('/Metadata')]=stream(w,xmp,Type=N('/Metadata'),Subtype=N('/XML'))
w.write(r/'InfoClaimedPDFA.pdf')
w,p,f=base();form=stream(w,b'BT /Nested 12 Tf 0 0 Td (Nested font) Tj ET',Type=N('/XObject'),Subtype=N('/Form'),BBox=A([I(0),I(0),I(300),I(100)]),Resources=d(Font=d(Nested=f)))
p[N('/Resources')]=d(XObject=d(Form=form));p[N('/Contents')]=stream(w,b'q 1 0 0 1 50 700 cm /Form Do Q');w.write(r/'InfoNestedFont.pdf')
w,p,f=base();char=stream(w,b'600 0 0 0 600 700 d1 0 0 600 700 re f')
type3=w._add_object(d(Type=N('/Font'),Subtype=N('/Type3'),FontBBox=A([I(0),I(0),I(600),I(700)]),FontMatrix=A([__import__('pypdf').generic.FloatObject(.001),I(0),I(0),__import__('pypdf').generic.FloatObject(.001),I(0),I(0)]),CharProcs=d(A=char),Encoding=d(Type=N('/Encoding'),Differences=A([I(65),N('/A')])),FirstChar=I(65),LastChar=I(65),Widths=A([I(600)]),Resources=d()))
p[N('/Resources')]=d(Font=d(F1=type3));p[N('/Contents')]=stream(w,b'BT /F1 18 Tf 50 700 Td (A) Tj ET');w.write(r/'InfoType3.pdf')
w,p,f=base();icc=stream(w,Path('/System/Library/ColorSync/Profiles/sRGB Profile.icc').read_bytes(),N=I(3));w._root_object[N('/OutputIntents')]=A([w._add_object(d(Type=N('/OutputIntent'),S=N('/GTS_PDFA1'),OutputConditionIdentifier=T('sRGB'),DestOutputProfile=icc))]);p['/Resources'][N('/ColorSpace')]=d(CS1=A([N('/ICCBased'),icc]));w.write(r/'InfoICC.pdf')
w,p,f=base()
desc=w._add_object(d(Type=N('/FontDescriptor'),FontName=N('/UnicodeFont'),Flags=I(4),FontBBox=A([I(0),I(0),I(1000),I(1000)]),Ascent=I(800),Descent=I(-200),CapHeight=I(700),ItalicAngle=I(0),StemV=I(80)))
cid=w._add_object(d(Type=N('/Font'),Subtype=N('/CIDFontType2'),BaseFont=N('/UnicodeFont'),CIDSystemInfo=d(Registry=T('Adobe'),Ordering=T('Identity'),Supplement=I(0)),FontDescriptor=desc,DW=I(1000)))
font=w._add_object(d(Type=N('/Font'),Subtype=N('/Type0'),BaseFont=N('/UnicodeFont'),Encoding=N('/Identity-H'),DescendantFonts=A([cid])))
p[N('/Resources')]=d(Font=d(F1=font));p[N('/Contents')]=stream(w,b'BT /F1 18 Tf 50 700 Td <0041> Tj ET');w.write(r/'InfoType0.pdf')
w,p,f=base();p[N('/Contents')]=stream(w,b'q 72 0 0 72 50 50 cm BI /W 1 /H 1 /BPC 8 /CS /RGB /F /AHx ID ff0000> EI Q');w.write(r/'InfoInlineImage.pdf')
w,p,f=base();w.add_attachment('../Folder\\Dangerous.txt', b'iPS2PDF embedded attachment\n')
# Word-generated PDFs can omit the required /Type entry from an attachment stream.
filespec=w._root_object['/Names']['/EmbeddedFiles']['/Names'][1].get_object();filespec['/EF']['/F'].get_object().pop(N('/Type'));w.write(r/'InfoAttachment.pdf')
w,p,f=base();w._info.get_object().pop(N('/Title'));xmp=b'''<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title><rdf:Alt><rdf:li xml:lang="x-default">XMP-only title</rdf:li></rdf:Alt></dc:title></rdf:Description></rdf:RDF></x:xmpmeta>''';w._root_object[N('/Metadata')]=stream(w,xmp,Type=N('/Metadata'),Subtype=N('/XML'));w.write(r/'InfoXMPTitle.pdf')

from pathlib import Path
import re, zlib
root=Path(__file__).resolve().parents[2]
r=root/'Tests/Unit/Fixtures'
# Preserve original encrypted objects and replace only the cross-reference container.
source=(r/'InfoEncrypted-AES-128.pdf').read_bytes()
xref=int(re.findall(rb'startxref\s+(\d+)',source)[-1])
trailer=re.search(rb'trailer\s*(<<.*?>>)\s*startxref',source[xref:],re.S).group(1)
rows=source[xref:].split(b'trailer')[0].splitlines()
size=int(rows[1].split()[1]); entries=[]
for row in rows[2:2+size]:
 off,gen,kind=row.split();entries.append(bytes([1 if kind==b'n' else 0])+int(off).to_bytes(4,'big')+int(gen).to_bytes(2,'big'))
entries.append(b'\1'+xref.to_bytes(4,'big')+b'\0\0')
payload=zlib.compress(b''.join(entries))
dictionary=re.sub(rb'/Size\s+\d+',b'/Size '+str(size+1).encode(),trailer)[:-2]+f' /Type /XRef /W [1 4 2] /Filter /FlateDecode /Length {len(payload)} >>'.encode()
result=source[:xref].replace(b'%PDF-1.3',b'%PDF-1.5',1)+f'{size} 0 obj\n'.encode()+dictionary+b'\nstream\n'+payload+b'\nendstream\nendobj\nstartxref\n'+str(xref).encode()+b'\n%%EOF\n'
(r/'InfoEncryptedXRefStream.pdf').write_bytes(result)
# Append a valid incremental catalog update, preserving the original trailer entries.
rootnum=int(re.search(rb'/Root\s+(\d+)',trailer).group(1))
cat=re.search(fr'{rootnum} 0 obj\s*(<<.*?>>)\s*endobj'.encode(),source,re.S).group(1)
offset=len(source)
append=f'{rootnum} 0 obj\n'.encode()+cat[:-2]+b' /Version /1.7 >>\nendobj\n'
newxref=offset+len(append)
updated_trailer=trailer[:-2]+f' /Prev {xref} >>'.encode()
append+=f'xref\n{rootnum} 1\n{offset:010} 00000 n \ntrailer\n'.encode()+updated_trailer+f'\nstartxref\n{newxref}\n%%EOF\n'.encode()
(r/'InfoEncryptedIncremental.pdf').write_bytes(source+append)

# Use the local Ghostscript font program for the two embedding variants.
import subprocess
for name, subset in [('InfoEmbeddedSubset', 'true'), ('InfoEmbeddedFull', 'false')]:
 subprocess.run(['gs', '-q', '-dBATCH', '-dNOPAUSE', '-sDEVICE=pdfwrite',
  '-dEmbedAllFonts=true', '-dSubsetFonts='+subset, '-sOutputFile='+str(r/(name+'.pdf')),
  '-c', '<</NeverEmbed []>> setdistillerparams', '-f', str(r/'InfoPlain.pdf')], check=True)
