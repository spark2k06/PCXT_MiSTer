fp = open('splash.txt')
lines = fp.readlines()
fp.close()

attr = ' 07 ' # char attribute
cols = 80 # columns
rows = 25 # rows
out = ''

rows_count = rows
for line in lines:
    rows_count = rows_count -1
    line = line.replace('\n', '')
    col_count = cols
    for c in line:
        col_count = col_count - 1
        hex_str = hex(ord(c))		
        out = out + hex_str.replace('0x', '').upper() + attr
        if col_count == 0:
            break
    while (col_count > 0):
        col_count = col_count - 1
        out = out + '20' + attr
    
    if rows_count == 0:
        break
        
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
