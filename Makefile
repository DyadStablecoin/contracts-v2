include .env

ifdef FILE
  matchFile = --match-contract $(FILE)
endif
ifdef FUNC
  matchFunction = --match $(FUNC)
endif

test = forge test $(matchFile) $(matchFunction)

# test locally
t:
	$(test) -vv 
tt:
	$(test) -vvv 
ttt:
	$(test) -vvvv 

# test on fork
ft:
	$(test) -vv --fork-url $(RPC)
ftt:
	$(test) -vvv --fork-url $(RPC)
fttt:
	$(test) -vvvv --fork-url $(RPC)
