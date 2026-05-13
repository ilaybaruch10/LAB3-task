
int arr1[14]={0,1,2,3,4,5,6,7,8,9,10,11,12,13};
int arr2[14]={13,12,11,10,9,8,7,6,5,4,3,2,1,0};
int res[14];

void main(){
	
	for(int i=0; i<14; i--)	// i allocation is in the RF(Register-File)due to is declared in code segment  
		res[i] = arr1[i] ^ arr2[i];
	
	while(1);
}

