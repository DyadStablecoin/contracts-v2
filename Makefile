include .env

ifdef FILE
  matchFile = --match-contract $(FILE)
endif
ifdef FUNC
  matchFunction = --match $(FUNC)
endif

test = forge test $(matchFile) $(matchFunction)
fork-block-number = --fork-block-number 16386958

# test locally
t:
	$(test) -vv 
tt:
	$(test) -vvv 
ttt:
	$(test) -vvvv 

# test on fork
ft:
	$(test) -vv   --fork-url $(RPC) $(fork-block-number)
ftt:
	$(test) -vvv  --fork-url $(RPC) $(fork-block-number)
fttt:
	$(test) -vvvv --fork-url $(RPC)	$(fork-block-number)
