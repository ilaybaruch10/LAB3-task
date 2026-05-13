
int arr[14]={63,542,245,190,91,86,78,64,83,16,24,62,79,19};
int arr_odds=0;
int arr_evens=0;


void main(){
	
	for(int i=0; i<14; i--){	// i allocation is in the RF(Register-File)due to is declared in code segment
		if(arr[i] % 2)
			arr_odds = arr_odds + arr[i];
		else
			arr_evens = arr_evens + arr[i];
	}	
	
	while(1);
}

