fp = open('splash.txt')
fp_ba = open('splash_ba.txt')
fp_fa = open('splash_fa.txt')
lines = fp.readlines()
lines_ba = fp_ba.readlines()
lines_fa = fp_fa.readlines()
fp.close()
fp_ba.close()
fp_fa.close()

attr = ' 07 ' # char attribute
cols = 80 # columns
rows = 25 # rows
out = ''

rows_count = rows
vcount = 0
hcount = 0

for line in lines:
    rows_count = rows_count -1
    line = line.replace('\n', '')
    col_count = cols
    for c in line:
        attr = ' '
        if lines_ba[vcount][hcount] not in ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'):
            attr = attr + '0'
        else:
            attr = attr + lines_ba[vcount][hcount]
            
        if lines_fa[vcount][hcount] not in ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'):
            attr = attr + '7'
        else:
            attr = attr + lines_fa[vcount][hcount]

        attr = attr + ' '
        col_count = col_count - 1
        hex_str = hex(ord(c))		
        out = out + hex_str.replace('0x', '').upper() + attr
        hcount = hcount + 1
        if col_count == 0:
            break

        

    while (col_count > 0):
        col_count = col_count - 1
        out = out + '20' + attr
    
    if rows_count == 0:
        break
        
    vcount = vcount + 1
    hcount = 0

while (rows_count > 0):    
    rows_count = rows_count -1
    col_count = cols
    while (col_count > 0):
        col_count = col_count - 1
        out = out + '20' + attr

out = out.strip()

fp = open('splash.hex', 'w+')
fp.write(out)
fp.close()
