data segment:	;DTCM content
arr1 dc16 0,1,2,3,4,5,6,7,8,9,10,11,12,13
arr2 dc16 13,12,11,10,9,8,7,6,5,4,3,2,1,0
res ds16 14

code segment:	;ITCM content
mov r1,arr1
mov r2,arr2
mov r3,res
mov r4,0
mov r5,1
mov r6,14
ld  r7,0(r1)
ld  r8,0(r2)
xor r9,r7,r8
st  r9,0(r3)
add r1,r1,r5
add r2,r2,r5
add r3,r3,r5
add r4,r4,r5
sub r10,r4,r6 
jlo -10
done
nop
jmp -2


