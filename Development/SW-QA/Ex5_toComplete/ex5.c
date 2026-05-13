
int arr1[14]={63,542,245,190,91,86,78,64,83,16,24,62,79,19};
int arr2[14]={13,312,141,160,92,88,71,63,59,14,43,12,71,90};
int res[14];


void main(){
	
	for(int i=0; i<14; i--){	// i allocation is in the RF(Register-File)due to is declared in code segment
		if(i % 2)
			res[i] = arr1[i] + arr2[i];
		else
			res[i] = arr1[i] - arr2[i];
	}	
	
	while(1);
}

