##  ----------------------------------------  ##
##                                            ##
##            Phrynomics Functions            ##
##              edited: 13Oct2014             ##
##                                            ##
##  ----------------------------------------  ##

library(ape)
library(phangorn)


################################################
####  Code to deal with data/tree analysis #####
################################################

deleteData <- function(data, type=NULL, taxa=NULL, percent=0.4){
#function to remove either random or certain taxa
#will remove TWO species sites from however much percent of sites
  data <- as.matrix(data)
  if(!is.null(type)){
    if(type == "random"){
      toDel <- sample(length(data), length(data)*percent)
      data[toDel] <- rep("N", length(toDel))
    }
  }  
  if(is.null(type)){
    dat2 <- data[taxa,]
    toDel <- sample(length(dat2), length(data)*percent)
    dat2[toDel] <- rep("N", length(toDel))
    data[taxa,] <- dat2
  }
  return(as.data.frame(data, stringsAsFactors=FALSE))
}

addInvariantData <- function(snpDataset, nsites){
#this function will add in nsites of invariabt data
#it will add an even amount of each base
  if(class(snpDataset) == "snp")
    snpDataset <- snpDataset$data
  ncols <- floor(nsites/4)
  bases <- c("A", "T", "C", "G")
  for(i in sequence(length(bases))){
    snpDataset <- cbind(snpDataset, matrix(rep(bases[i], ncols*dim(snpDataset)[1]), ncol=ncols))
  }  
  return(snpDataset)  
}

append.MrBayes <- function(file, data=c("snps", "full"), type=c("asc, nonasc"), nst=NULL){
  f <- file
  if(data == "snps"){
    if (type == "asc")
      type <- "variable"  #coding=variable
    if (type == "nonasc")
      type <- "all"  #coding=all
  }
  write(paste("BEGIN mrbayes;"), file=f, append=TRUE)
  write(paste("outgroup GAWI1;"), file=f, append=TRUE)
  write(paste(""), file=f, append=TRUE)
  write(paste("set autoclose=yes;"), file=f, append=TRUE)
  write(paste("set seed=", floor(runif(1, min=1, max=10^6)), ";", sep=""), file=f, append=TRUE)
  if(data == "snps")
    write(paste("lset rates=equal coding=", type, ";", sep=""), file=f, append=TRUE)
  if(data == "full")
    write(paste("lset rates=invgamma nst=", nst, ";", sep=""), file=f, append=TRUE)
  write(paste("prset brlenspr=unconstrained:gammadir(1,1,1,1);"), file=f, append=TRUE)
  write(paste(""), file=f, append=TRUE)
  write(paste("mcmc nchains=4 ngen=2000000 stoprule=yes printfreq=20000 samplefreq=1000;"), file=f, append=TRUE)
  write(paste("sumt conformat=simple burnin=500;", sep=""), file=f, append=TRUE)
  write(paste("sump burnin=500;", sep=""), file=f, append=TRUE)
  write(paste(""), file=f, append=TRUE)
  write(paste("END;"), file=f, append=TRUE)
}

GetModel <- function(name){
  if(length(grep("GTR", name)) > 0){
    if(length(grep("ASC", name)) > 0)
      return("ASC")
    return("GTR")
  }
  if(length(grep("full", name)) > 0)
    return("full")
}

GetLevel <- function(name){
  splits <- strsplit(name, "[_./]")[[1]]
  return(splits[grep("^c", splits)])
}

GetRaxMLTreeLength <- function(RAxML.infoFile){
  treelength <- system(paste("grep Tree-Length: ", RAxML.infoFile), intern=T)
  TreeLength <- gsub("Tree-Length: ", "", treelength, fixed=T)
  return(TreeLength)
}


getMissingDataAmount <- function(filename){
  split1 <- strsplit(filename, "\\D+")[[1]][2]
  return(as.numeric(split1))
}

CreateTreeList <- function(filenames, analysis="RAxML"){
  analysis <- match.arg(arg=analysis, choices=c("RAxML", "MrBayes"), several.ok=FALSE)
  TreeList <- list()
  if(analysis == "RAxML"){
    for(i in sequence(length(filenames))){
      TreeList[[i]] <- ladderize(read.tree(filenames[i]))
      names(TreeList)[[i]] <- filenames[i]
    }
  }
  if(analysis == "MrBayes"){
    for(i in sequence(length(filenames))){
      TreeList[[i]] <- read.nexus(filenames[i])
      if(class(TreeList[[i]]) == "multiPhylo")
        TreeList[[i]] <- TreeList[[i]][[1]]
      TreeList[[i]] <- ladderize(TreeList[[i]])
      names(TreeList)[[i]] <- filenames[i]
    }
  }
  return(TreeList)
}

GetAnalysis <- function(fileName){
  return(strsplit(fileName, "[._]")[[1]][3])
}

CreateTreeMatrix <- function(trees) {
#Creates a matrix of file names that correspons to missing data amounts (rows) and model (cols)
#GTRorFULL will create the tree matrix comparison with either ASC and GTR data or ASC and full data.
  missingDataTypes <- sapply(trees, getMissingDataAmount)
  analy <- sapply(trees, GetAnalysis)
  runs <- unique(analy)
  #ASCtrees <- grep("ASC_", trees)
  #GTRtrees <- c(grep("3_GTR", trees), grep("GTR_", trees))
  #FULLtrees <- c(grep("full", trees), grep("c*p3.nex", trees))
  treeMatrix <- matrix(nrow=length(unique(missingDataTypes)), ncol=length(runs))
  rownames(treeMatrix) <- paste("s", unique(missingDataTypes), sep="")
  colnames(treeMatrix) <- runs
  for(i in sequence(dim(treeMatrix)[1])) {
    multFiles <- trees[missingDataTypes == sub("s", "", rownames(treeMatrix)[i])]
    tt <- NULL
    for(j in sequence(length(runs))){
      tt <- c(tt, grep(runs[j], multFiles))
    }
    treeMatrix[i,] <- multFiles[tt]
  }
  return(as.data.frame(treeMatrix, stringsAsFactors=FALSE))
}

assTrees <- function(TreeMatrixName, ListOfTrees){
  return(ListOfTrees[which(names(ListOfTrees) == TreeMatrixName)])
}

AddTreeDist <- function(TreeMatrixName, ListOfTrees){
#Uses phangorn to calculate Steel & Penny whole-tree metrics
#Steel M. A. and Penny P. (1993) Distributions of tree comparison metrics - some new results, Syst. Biol.,42(2), 126-141
  treeDists <- NULL
  for(row in sequence(dim(TreeMatrixName)[1])){
    twoTrees <- c(assTrees(TreeMatrixName[row,1], ListOfTrees), assTrees(TreeMatrixName[row,2], ListOfTrees))
    if(length(twoTrees) == 2){
      dists <- phangorn::treedist(twoTrees[[1]], twoTrees[[2]])
      treeDists <- rbind(treeDists, dists)
    }
    if(length(twoTrees) != 2){
      treeDists <- rbind(treeDists, dists=rep(NA, 4))
    }
  }
  cbind(TreeMatrixName, treeDists)
}

##  Kuhner & Felsenstein Branch Length distance measure (Kscore)
AddBLD <- function(TreeMatrixName, ListOfTrees){
#Kuhner, M. K. and J. Felsenstein. 1994. A simulation comparison of phylogeny algorithms under equal and unequal evolutionary rates. Molecular Biology and Evolution 11: 459-468.
#This uses Soria-Carrasco & Jose Castresana perl script to calculate K-score via terminal
#Soria-Carrasco, V., Talavera, G., Igea, J., and Castresana, J. (2007). The K tree score: quantification of differences in the relative branch length and topology of phylogenetic trees. Bioinformatics 23, 2954-2956.
#http://molevol.cmima.csic.es/castresana/Ktreedist.html
  Kscores <- NULL
  for (row in sequence(dim(TreeMatrixName)[1])) {
    twoTrees <- c(assTrees(TreeMatrixName[row,1], ListOfTrees), assTrees(TreeMatrixName[row,2], ListOfTrees))
    if(length(twoTrees) == 2){
      twoTrees[[1]]$node.label <- NULL
      twoTrees[[2]]$node.label <- NULL
      write.nexus(twoTrees[[1]], file="tree1")  #prog will not run with bootstrap vals
      write.nexus(twoTrees[[2]], file="tree2")  
      runProg <- system("perl /Applications/PhylogeneticsPrograms/Ktreedist_v1/Ktreedist.pl -rt tree1 -ct tree2 -a", intern=T)
      vals <- grep("UNTITLED", runProg)[2]
      kscore <- as.numeric(strsplit(runProg[vals], " ")[[1]][grep("\\d+", strsplit(runProg[vals], " ")[[1]])])
      names(kscore) <- c("Kscore", "ScaleFactor", "SymmDiff", "Npartitions")
      Kscores <- rbind(Kscores, kscore)
    }
    if(length(twoTrees) != 2){
      Kscores <- rbind(Kscores, kscore=rep(NA, 4))
    }
  }
  cbind(TreeMatrixName, Kscores)
}


GetEdgeList <- function(tree) {
  desc.order <- tree$edge[,2]  #store this order so that you can go back to it after
  tipList <- cbind(tree$edge, tree$edge[, 2] %in% tree$edge[, 1], tree$edge.length)
  tipList <- as.data.frame(tipList, stringsAsFactors=F)
  colnames(tipList) <- c("anc", "desc", "class", "branchlength")
  tipList[which(tipList[,3] == 0), 3] <- "tip"
  tipList[which(tipList[, 3] == 1), 3] <- "internal"
  tipList$support <- rep(0, dim(tipList)[1])
  tipList  <- tipList[order(tipList[,2]), ]  # reorder edge list so that you can assign the correct support vals
  if(!is.null(tree$node.label))
    tipList$support[which(tipList$class == "internal")] <- as.numeric(tree$node.label)[-1] #node support comes in with an extra space in the beginning, so it has to be cleaved then readded for plotting.
  tipList <- tipList[match(desc.order , tipList[,2]),]
  options(digits=15)
  tipList$branchlength <- as.numeric(tipList$branchlength)
  return(data.frame(tipList, stringsAsFactors = F))
}


nodeOffspring <- function(tree, anc.node) {
  rows <- which(tree$edge[, 1] == anc.node)
  return(tree$edge[rows, 2])
}

nodeLeaves <- function(tree, anc.node) {
  ntips <- Ntip(tree)
  if (anc.node <= ntips) 
    return(tree$tip.label[as.numeric(anc.node)])
  listTaxa <- character()
  descendents <- nodeOffspring(tree, anc.node)
  for (j in descendents) {
    if (j <= ntips) 
      listTaxa <- c(listTaxa, tree$tip.label[as.numeric(j)])
    else listTaxa <- c(listTaxa, nodeLeaves(tree, j))  #recursive....
  }
  return(listTaxa)
}

CheckSharedMonophy <- function(t1.node, tree1, tree2) {
#t1.node should be desc.nodes--a single edge (ex: 74)
#returns T/F if the taxa from that edge match a monophyletic group in tree 2  
  t1.taxa <- nodeLeaves(tree1, t1.node)
  if(length(t1.taxa) == 1)
    return(TRUE)
  mrca <- getMRCA(tree2, t1.taxa)
  t2.taxa <- nodeLeaves(tree2, mrca)
  if(all(t1.taxa %in% t2.taxa) && all(t2.taxa %in% t1.taxa))
    return(TRUE)
  else return(FALSE)  
}

GetCorrespondingEdge <- function(t1.node, tree1, tree2) {
  if(CheckSharedMonophy(t1.node, tree1, tree2)) {
    t1.taxa <- nodeLeaves(tree1, t1.node)
    if(length(t1.taxa) == 1)
      return(which(tree2$tip.label == t1.taxa))
    return(getMRCA(tree2, t1.taxa))
  }
  else return(0)
}
#GetCorrespondingEdge(77, tree1, tree2)

GetCorresonding <- function(corr.desc, t2){  
  return(t2[which(t2$desc == corr.desc),])
}

GetSingleEdgeColor <- function(relativeBLdiff, scale=1) {
  if(scale == 1){
    if(is.na(relativeBLdiff))  return(NA)
    else if (relativeBLdiff < -100) return(rgb(51,51,255, maxColorValue =255)) #underestimate over 10%
    else if (relativeBLdiff <= 100) return("gray")  #plus/minus 10%
    else if (relativeBLdiff < 200) return(rgb(255,255,102, maxColorValue=255))
    else if (relativeBLdiff < 300) return(rgb(255,178,102, maxColorValue=255))
    else if (relativeBLdiff < 400) return(rgb(225,128,0, maxColorValue=255))
    else if (relativeBLdiff < 500) return(rgb(225,0,0, maxColorValue=255))
    else return(rgb(153,0,0, maxColorValue=255))	  
  }
  if(scale == 2){
    if(is.na(relativeBLdiff))  return(NA)
    else if (relativeBLdiff < -100) return(rgb(51,51,255, maxColorValue=255))
    else if (relativeBLdiff < -50) return(rgb(51,194,255, maxColorValue =255))
    else if (relativeBLdiff < -25) return(rgb(51,255,241, maxColorValue=255))
    else if (relativeBLdiff <= 0) return("gray")  #plus/minus 50%
    else if(relativeBLdiff < 25) return("gray")
    else if (relativeBLdiff > 25) return(rgb(196,156,100, maxColorValue =255)) #overestimate over 25%
    else return(rgb(153,0,0, maxColorValue=255))
  }
}
#GetSingleEdgeColor(30)

ReturnMinCI <- function(x, vstat){
  if(x != 0)
    return(vstat[which(vstat$Median == x),3])
  else return(0)
}

ReturnMaxCI <- function(x, vstat){
  if(x != 0)
    return(vstat[which(vstat$Median == x),4])
  else return(0)
}

remove_outliers <- function(x, na.rm = TRUE, ...) {
  qnt <- quantile(x, probs=c(.25, .75), na.rm = na.rm, ...)
  H <- 1.5 * IQR(x, na.rm = na.rm)
  y <- x
  y[x < (qnt[1] - H)] <- NA
  y[x > (qnt[2] + H)] <- NA
  return(y[-which(is.na(y))])
}

MakeBranchLengthMatrix <- function(tree1, tree2, analysis="RAxML", dataset=NULL){  
  t1 <- GetEdgeList(tree1) 
  t2 <- GetEdgeList(tree2) 
  desc.nodes <- t1[,2]
  t1$present <- sapply(desc.nodes, CheckSharedMonophy, tree1=tree1, tree2=tree2) 
  t1$corr.anc <- sapply(t1[,1], GetCorrespondingEdge, tree1=tree1, tree2=tree2)
  t1$corr.desc <- sapply(desc.nodes, GetCorrespondingEdge, tree1=tree1, tree2=tree2)
  t1$corr.BL <- rep(0, dim(t1)[1])
  t1$corr.support <- rep(0, dim(t1)[1])
  for(i in which(t1$present)){
    t1$corr.BL[i] <- GetCorresonding(t1$corr.desc[i], t2)[[4]]
    t1$corr.support[i] <- GetCorresonding(t1$corr.desc[i], t2)[[5]]    
  }
  t1$BL.DIFF <- t1$corr.BL - t1$branchlength #tree B - tree A
  t1$BL.DIFF[which(!t1$present)] <- 0  #remove data when not comparable
  t1$relativeBLdiff <- (t1$BL.DIFF / t1$branchlength) * 100
  t1$edgeColor1 <- sapply(t1$relativeBLdiff, GetSingleEdgeColor, scale=1)
  t1$edgeColor2 <- sapply(t1$relativeBLdiff, GetSingleEdgeColor, scale=2)
  t1$edgelty <- rep(3, dim(t1)[1])
  t1$edgelty[which(t1$present)] <- 1
  if(analysis == "MrBayes"){
    vstat1 <- read.table(system(paste("ls ASC_", dataset, "*.vstat", sep=""), intern=TRUE), row.names=1, stringsAsFactors=FALSE, skip=1)
    vstat2 <- read.table(system(paste("ls GTR_", dataset, "*.vstat", sep=""), intern=TRUE), row.names=1, stringsAsFactors=FALSE, skip=1)
    colnames(vstat1) <- colnames(vstat2) <- read.table(system(paste("ls ASC_", dataset, "*.vstat", sep=""), intern=TRUE), row.names=1, stringsAsFactors=FALSE)[1,]
    t1$min.ASC.BL.CI <- sapply(t1$branchlength, ReturnMinCI, vstat=vstat1)
    t1$max.ASC.BL.CI <- sapply(t1$branchlength, ReturnMaxCI, vstat=vstat1)
    t1$min.GTR.BL.CI <- sapply(t1$corr.BL, ReturnMinCI, vstat=vstat2)
    t1$max.GTR.BL.CI <- sapply(t1$corr.BL, ReturnMaxCI, vstat=vstat2)
  }
  return(t1)
}

makeNumberwithcommas <- function(number){
  string <- strsplit(as.character(number), "")[[1]]
  if(length(string) > 3){
    string <- paste(paste(paste(string[1:(length(string)-3)], collapse=""), ",", sep=""), paste(string[-1:-(length(string)-3)], collapse=""), sep="")
  }
  else string <- paste(string, collapse="")
  return(string)
}

GetSupportValue <- function(lineNumber, tstat.table){
  lineNumber <- as.numeric(lineNumber)
  if(lineNumber %in% tstat.table[,1])
    return(tstat.table[which(tstat.table[,1] == lineNumber), 3])
}


CompareMrBayesPosteriors <- function(run1, run2, ntax=73){
#run1 and run2 should correspond with ASC and GTR models
#should be able to give it the treeMatrix and have it find the associated files
  linesToSkip <- GetLinesToSkip(paste(strsplit(run1, ".", fixed=TRUE)[[1]][1], "*.parts", sep=""))
  ASCbipartsFile <- read.table(system(paste("ls ",strsplit(run1, ".", fixed=TRUE)[[1]][1], "*.parts", sep=""), intern=TRUE), stringsAsFactors=FALSE, skip=linesToSkip+1)
  ASCbipartsFile <- ASCbipartsFile[-which(ASCbipartsFile == "ID"):-dim(ASCbipartsFile)[1],]
  linesToSkip <- GetLinesToSkip(paste(strsplit(run2, ".", fixed=TRUE)[[1]][1], "*.parts", sep=""))
  GTRbipartsFile <- read.table(system(paste("ls ",strsplit(run2, ".", fixed=TRUE)[[1]][1], "*.parts", sep=""), intern=TRUE), skip=linesToSkip+1, stringsAsFactors=FALSE)
  GTRbipartsFile <- GTRbipartsFile[-which(GTRbipartsFile == "ID"):-dim(GTRbipartsFile)[1],]
  linesToSkip <- GetLinesToSkip(paste(strsplit(run1, ".", fixed=TRUE)[[1]][1], "*.tstat", sep=""))
  ASCtstatFile <- read.table(system(paste("ls ", strsplit(run1, ".", fixed=TRUE)[[1]][1], "*.tstat", sep=""), intern=TRUE), skip=linesToSkip+1, stringsAsFactors=FALSE)
  linesToSkip <- GetLinesToSkip(paste(strsplit(run2, ".", fixed=TRUE)[[1]][1], "*.tstat", sep=""))
  GTRtstatFile <- read.table(system(paste("ls ", strsplit(run2, ".", fixed=TRUE)[[1]][1], "*.tstat", sep=""), intern=TRUE), skip=linesToSkip+1, stringsAsFactors=FALSE)  
  ASC.bipartInternalNodes <- (ntax+1):max(as.numeric(ASCbipartsFile[,1]))
  ASC.results <- matrix(nrow=length(ASC.bipartInternalNodes), ncol=5)
  ASC.results[,1] <- ASC.bipartInternalNodes
  ASC.results[,2] <- sapply(ASC.bipartInternalNodes, GetSupportValue, tstat.table=ASCtstatFile)
  for(line in sequence(length(ASC.bipartInternalNodes))){
    pattern <- ASCbipartsFile[which(ASCbipartsFile[,1] == ASC.bipartInternalNodes[line]),2]
    ASC.results[line,3] <- pattern
    corr.line <- GTRbipartsFile[which(GTRbipartsFile[,2] == pattern), 1]
    if(length(corr.line) == 0){
      ASC.results[line,4] <- NA
      ASC.results[line,5] <- 0
    }
    if(length(corr.line) > 0){
      ASC.results[line,4] <- corr.line
      ASC.results[line,5] <- GetSupportValue(corr.line, GTRtstatFile)
    }
  }
  GTR.bipartInternalNodes <- (ntax+1):max(as.numeric(GTRbipartsFile[,1]))
  GTR.results <- matrix(nrow=length(GTR.bipartInternalNodes), ncol=5)
  GTR.results[,4] <- GTR.bipartInternalNodes
  GTR.results[,5] <- sapply(GTR.bipartInternalNodes, GetSupportValue, tstat.table=GTRtstatFile)
  for(line in sequence(length(GTR.bipartInternalNodes))){
    pattern <- GTRbipartsFile[which(GTRbipartsFile[,1] == GTR.bipartInternalNodes[line]),2]
    GTR.results[line,3] <- pattern
    corr.line <- ASCbipartsFile[which(ASCbipartsFile[,2] == pattern), 1]
    if(length(corr.line) == 0){
      GTR.results[line,1] <- NA
      GTR.results[line,2] <- 0
    }
    if(length(corr.line) > 0){
      GTR.results[line,1] <- corr.line
      GTR.results[line,2] <- GetSupportValue(corr.line, ASCtstatFile)
    }
  }
results <- as.data.frame(rbind(ASC.results, GTR.results), stringsAsFactors=FALSE)
colnames(results) <- c("ASC.bipart.line", "ASC.support", "pattern", "GTR.bipart.line", "GTR.support")
results$ASC.support <- as.numeric(results$ASC.support)
results$GTR.support <- as.numeric(results$GTR.support)
return(results)
}

getColor <- function(BLtable, nonSigColor="gray", sigColor="red", method=c("varOverlap", "meanWithin")){
#for method, choose whether you want to distinguish significant deviants either by non-overlapping CI distributions or by the mean of the GTR BL not falling within the ASC distribution 
  method <- match.arg(method, choices=c("varOverlap", "meanWithin"))  
  if(is.null(BLtable$min.ASC.BL.CI))
    return(rep(nonSigColor, dim(BLtable)[1]))
  colorVector <- rep("NA", dim(BLtable)[1])
  for(i in sequence(dim(BLtable)[1])){
    if(BLtable$corr.BL[i] != 0){
      if(method == "meanWithin"){
        if(BLtable$min.ASC.BL.CI[i] < BLtable$corr.BL[i] && BLtable$corr.BL[i] < BLtable$max.ASC.BL.CI[i])
          colorVector[i] <- nonSigColor
        else colorVector[i] <- sigColor
      }
      if(method == "varOverlap"){
        if(BLtable$min.GTR.BL.CI[i] < BLtable$max.ASC.BL.CI[i] || BLtable$min.ASC.BL.CI[i] < BLtable$max.GTR.BL.CI[i])
          colorVector[i] <- nonSigColor
        else  colorVector[i] <- sigColor
      }
    }
  }
return(colorVector)
}

GetAncestors <- function(treeEdgeMatrix, tip) {
#function to tree traverse back to the root to get node numbers
  Root <- min(treeEdgeMatrix[,1])
  is.done <- FALSE
  desc <- tip
  desc.vector <- tip
  while(!is.done){
    a <- which(treeEdgeMatrix[, 2] == desc)
    b <- treeEdgeMatrix[a, 1]
    desc.vector <- c(desc.vector, b)
    if(b == Root)
      is.done <- TRUE
    else
      desc <- b
  }
  return(desc.vector)
}

CalculateTotalTipBLError <- function(BL.AllTrees) {
#this function should take BL.AllTrees matrix and return root to tip totals BL.DIFF
  tips <- BL.AllTrees[which(BL.AllTrees$class == "tip"), 2]
  tipPathDifferences <- NULL
  for(i in tips){
    ancs <- GetAncestors(BL.AllTrees[,1:2], tips[i])
    pathDifferences <- BL.AllTrees[which(BL.AllTrees[,2] %in% ancs), 12]  #column 12 is relativeBLdiff (which can be pos or neg)
    totalPathDifference <- sum(abs(pathDifferences))  # sum absolute value path differences # relative number
    tipPathDifferences <- c(tipPathDifferences, totalPathDifference)
  }
  names(tipPathDifferences) <- paste("tip", tips, sep="")
  return(tipPathDifferences)
}

GetJustTipBLError <- function(BL.AllTrees){
# this function will return a vector of BL differences for just tips
  tips <- BL.AllTrees[which(BL.AllTrees$class == "tip"), 2]
  tipDifferences <- rep(0, length(tips))
  for(i in tips){
    tipDifferences[i] <- BL.AllTrees[which(BL.AllTrees[,2] == tips[i]), 12]  #column 12 is relativeBLdiff (which can be pos or neg)
    names(tipDifferences)[i] <- paste("tip", tips[i], sep="")
  }
  return(tipDifferences)
}


getBestTrees <- function(model, dataset, analysis){
# sloppy function that returns file names for raxml and 20 randoms for MrBayes.
# used for making an RF matrix
  if(analysis == "RAxML")
    return(system(paste("ls RAxML_bestTree*", dataset, "*", model, "*_REP*", sep=""), intern=TRUE))
  if(analysis == "MrBayes"){
    #gather 20 random trees from posterior
    file <- system(paste("ls ", model, "_", dataset, "noAmbigs.nex.run1.t", sep=""), intern=TRUE)
    random20 <- floor(runif(20, min=1, max=length(names(read.nexus(file)))))
    #allBItrees <- names(read.nexus(file))  #will take 185 days to run
    return(list(file=file, random20=random20))
  }
}

makeRFdistanceMatrix <- function(treeList, analysis){
# this function will take a list of file names (treeList)
# creates a pairwise matrix comparing each tree and calculating RF
  if(analysis == "RAxML")
    compare <- matrix(nrow=length(treeList), ncol=length(treeList))
  if(analysis == "MrBayes")
    compare <- matrix(nrow=length(treeList$random20), ncol=length(treeList$random20))
  for(i in sequence(dim(compare)[1])){
    if(analysis == "RAxML")
      tree1 <- read.tree(treeList[i])    
    if(analysis == "MrBayes"){
      trees <- read.nexus(treeList$file)
      tree1 <- trees[treeList$random20[i]][[1]]
    }
      for(j in sequence(dim(compare)[1])){
        if(i != j){
          if(analysis == "RAxML")
            tree2 <- read.tree(treeList[j])    
          if(analysis == "MrBayes")
            tree2 <- trees[treeList$random20[j]][[1]]
          compare[i,j] <- phangorn::treedist(tree1, tree2)[[1]]  #symmetric difference
        }
      }
    }
return(compare)
}

GetRFmatrix <- function(analysis) {
#this function will take 
  models <- c("ASC", "GTR")
  dataset <- paste("c", seq(from=5, to=70, by=5), "p3", sep="")
  RFdists <- NULL
  RFdistnames <- NULL
  RFdistMatrix <- matrix(nrow=28, ncol=4)
  place <- 0
  for(i in sequence(length(models))){
    for(j in sequence(length(dataset))){
      startTime <- proc.time()[[3]]
      place <- place+1
      print(place)
      RFdist <- NULL
      RFdistname <- NULL
      RFdist <- mean(makeRFdistanceMatrix(getBestTrees(models[i], dataset[j], analysis), analysis), na.rm=TRUE)    
      print(proc.time()[[3]]-startTime)
      RFdists <- c(RFdists, RFdist)
      RFdistname <- paste(models[i], dataset[j], sep="")
      print(paste(models[i], dataset[j], sep=""))
      RFdistnames <- c(RFdistnames, RFdistname)
      RFdistMatrix[place,] <- c(models[i], dataset[j], j, RFdist)
    }
    names(RFdists) <- RFdistnames
  }
  return(RFdists)
}




################################################
#################   END   ######################
################################################




################################################
#######    Post Analysis Scraping   ############
################################################


GetRAxMLStatsPostAnalysis <- function(workingDirectoryOfResults) {
  startingDir <- getwd()
  setwd(workingDirectoryOfResults)
  vFiles <- system(paste("ls s*noAmbigs.phy"), intern=T)
  cFiles <- system(paste("ls s*full.phy"), intern=T)
  outFiles <- system("ls RAxML_info*", intern=T)
  results <- matrix(nrow=length(outFiles), ncol=10)
  for(i in sequence(length(outFiles))){
    if(length(grep("full", outFiles[i])) > 0){
      MissingDataLevel <- paste0("s", strsplit(outFiles[i], split="[A-z]+")[[1]][3])
      MissingDataSet <- paste0("s", strsplit(outFiles[i], split="[A-z]+")[[1]][3], "full")
      whichModel <- strsplit(outFiles[i], "[._]")[[1]][3]
      SNPdataset <- ReadSNP(vFiles[grep(MissingDataSet, cFiles)], fileFormat="phy", extralinestoskip=1)
      VariableSites <- sum(SNPdataset$nsites)
      numberLoci <- SNPdataset$nloci
    }
    if(length(grep("full", outFiles[i])) == 0){
      MissingDataLevel <- paste0("s", strsplit(outFiles[i], split="[A-z]+")[[1]][3])
      MissingDataSet <- paste0("s", strsplit(outFiles[i], split="[A-z]+")[[1]][3], "noAmbigs")
      whichModel <- strsplit(outFiles[i], "[._]")[[1]][3]
      SNPdataset <- ReadSNP(vFiles[grep(MissingDataSet, vFiles)], fileFormat="phy", extralinestoskip=1)
      VariableSites <- sum(SNPdataset$nsites)
      numberLoci <- SNPdataset$nloci
    }
    alignmentPatterns <- gsub("\\D", "", system(paste("grep 'distinct alignment patterns'", outFiles[i]), intern=T))
    Missing <-gsub("[A-Za-z:]+|[%]$", "", system(paste("grep 'Proportion of gaps and completely undetermined characters in this alignment:'", outFiles[i]), intern=T), perl=T)
    BootstrapTime <- strsplit(system(paste("grep 'Overall Time for '", outFiles[i]), intern=T), split="[A-Za-z:]+|[%]$", perl=T)[[1]][6]
    Likelihood <- strsplit(system(paste("grep 'Final ML Optimization Likelihood:'", outFiles[i]), intern=T), split="[A-Za-z:]+|[%]$", perl=T)[[1]][5]
    #Alpha <- gsub("[alpha: ]", "", system(paste("grep alpha: ", outFiles[i]), intern=T), perl=T)
    Alpha <- "0"
	TreeLength <- gsub("Tree-Length: ", "", system(paste("grep Tree-Length: ", outFiles[i]), intern=T), fixed=T)
    results[i,] <- c(MissingDataLevel, whichModel, numberLoci, VariableSites, alignmentPatterns, Missing, BootstrapTime, Likelihood, Alpha, TreeLength)
  }
  results <- data.frame(results, stringsAsFactors=FALSE)
  colnames(results) <- c("Level", "Model", "NumberLoci", "VariableSites", "AlignmentPatterns", "MissingData", "BootstrapTime", "Likelihood", "Alpha", "TreeLength")
  options(digits=10)
  results$Level <- as.factor(results$Level)
  results$Model <- as.factor(results$Model)
  results$NumberLoci <- as.numeric(results$NumberLoci)
  results$VariableSites <- as.numeric(results$VariableSites)
  results$AlignmentPatterns <- as.numeric(results$AlignmentPatterns)
  results$MissingData <- as.numeric(results$MissingData)
  results$BootstrapTime <- as.numeric(results$BootstrapTime)
  results$Likelihood <- as.numeric(results$Likelihood)
  results$Alpha <- as.numeric(results$Alpha)
  results$TreeLength <- as.numeric(results$TreeLength)
  setwd(startingDir)
  return(results)
}

GetTime <- function(RAxML_infofile){
  line <- system(paste("grep 'ML search took '", RAxML_infofile), intern=TRUE)[1]
  line <- gsub("[a-zA-Z]", "", line)
  secs <- strsplit(line, split=" +")[[1]][3]
  return(as.numeric(secs))
}

CreateTimeMatrix <- function(infoFiles){
## Creates a matrix of file names that corresponds to amount of missing data and the models. 
  missingDataTypes <- sapply(infoFiles, getMissingDataAmount)
  analy <- sapply(infoFiles, GetAnalysis)
  runs <- unique(analy)
  timeMatrix <- matrix(nrow=length(unique(missingDataTypes)), ncol=length(runs))
  rownames(timeMatrix) <- paste("s", unique(missingDataTypes), sep="")
  colnames(timeMatrix) <- runs
  for(row in rownames(timeMatrix)) {
    for(col in colnames(timeMatrix)){
      if(col == "full")
        whichInfoFile <- infoFiles[grep(paste0(col, "_out_", row, "full"), infoFiles)]
      if(col != "full")
        whichInfoFile <- infoFiles[grep(paste0(col, "_out_", row, "noAmbigs"), infoFiles)]      
      timeMatrix[row,col] <- GetTime(whichInfoFile)
    }
  }
  return(as.data.frame(timeMatrix, stringsAsFactors=FALSE))
}

GetSitePattern <- function(RAxML_infofile){
  line <- system(paste("grep 'Alignment Patterns: '", RAxML_infofile), intern=TRUE)[1]
  line <- gsub("Alignment Patterns: ", "", line)
  return(as.numeric(line))
}


CreateSitePatternMatrix <- function(infoFiles){
## Creates a matrix of file names that corresponds to amount of missing data and the models. 
  missingDataTypes <- sapply(infoFiles, getMissingDataAmount)
  analy <- sapply(infoFiles, GetAnalysis)
  runs <- unique(analy)
  spMatrix <- matrix(nrow=length(unique(missingDataTypes)), ncol=length(runs))
  rownames(spMatrix) <- paste("s", unique(missingDataTypes), sep="")
  colnames(spMatrix) <- runs
  for(row in rownames(spMatrix)) {
    for(col in colnames(spMatrix)){
      if(col == "full")
        whichInfoFile <- infoFiles[grep(paste0(col, "_out_", row, "full"), infoFiles)]
      if(col != "full")
        whichInfoFile <- infoFiles[grep(paste0(col, "_out_", row, "noAmbigs"), infoFiles)]      
      spMatrix[row,col] <- GetSitePattern(whichInfoFile)
    }
  }
  return(as.data.frame(spMatrix, stringsAsFactors=FALSE))
}



GetLinesToSkip <- function(file){
  return(length(suppressWarnings(system(paste("grep 'ID:' ", file, sep=""), intern=TRUE))))
}

GetMrBayesStatsPostAnalysis <- function(workingDirectoryOfResults){
  startingDir <- getwd()
  setwd(workingDirectoryOfResults)
  vFiles <- system("ls *noAmbigs.nex", intern=TRUE)  #num loci
  cFiles <- system("ls c*3.nex", intern=TRUE)  #num loci
  nexFiles <- c(vFiles, cFiles)
  pstatFiles <- system("ls *.pstat", intern=TRUE)  #tree length and alpha
  logFiles <- system("ls *log*", intern=TRUE)  
  results <- matrix(nrow=length(nexFiles), ncol=12)
  for(i in sequence(length(nexFiles))){
    MissingDataLevel <- paste("c", strsplit(nexFiles[i], "\\D+")[[1]][2], "p3", sep="")
    whichModel <- strsplit(nexFiles[i], "_")[[1]][1]
    if(length(grep("noAmbigs", nexFiles[i])) == 0)
      whichModel <- "full"
    numLociLine <- system(paste("grep DIMENSIONS", nexFiles[i]), intern=TRUE)
    numberLoci <- strsplit(numLociLine, "\\D+")[[1]][3]
    datName <- paste0(whichModel, "_c", strsplit(nexFiles[i], "\\D+")[[1]][2], "p3")
    dataName <- paste0("^", datName)
    if(length(grep("noAmbigs", nexFiles[i])) == 0){
      datName <- paste0("c", strsplit(nexFiles[i], "\\D+")[[1]][2], "p3")
      dataName <- paste0("^", datName)
    }
    if(length(pstatFiles[grep(dataName, pstatFiles)]) > 0) {
      pstats <- read.csv(pstatFiles[grep(dataName, pstatFiles)], sep="", skip=GetLinesToSkip(pstatFiles[grep(dataName, pstatFiles)]))
    }
    if(length(pstatFiles[grep(dataName, pstatFiles)]) == 0) {
      pstats <- NULL
    }
    treelength <- pstats[1, grep("mean", names(pstats), ignore.case=TRUE)]
    treelength.lowCI <- pstats[1, grep("lower", names(pstats), ignore.case=TRUE)]
    treelength.uppCI <- pstats[1, grep("upper", names(pstats), ignore.case=TRUE)]
    treelengthESS <- pstats[1, grep("avgESS", names(pstats), ignore.case=TRUE)]
    alpha <- pstats[2,2]
    alpha.lowCI <- pstats[2,4]
    alpha.uppCI <- pstats[2,5]
    alphaESS <- pstats[2,8]
    splitgrep <- paste0("log", datName)
    stdSplitLine <- system(paste("grep -A 1 'Summary statistics for partitions with frequency' ", logFiles[grep(splitgrep, logFiles)], sep=""), intern=T)[2]
    stdSplits <- gsub("          Average standard deviation of split frequencies = ", "", stdSplitLine)
    results[i,] <- c(MissingDataLevel, whichModel, numberLoci, treelength, treelength.lowCI, treelength.uppCI, treelengthESS, alpha, alpha.lowCI, alpha.uppCI, alphaESS, stdSplits)
  }  
  results <- data.frame(results, stringsAsFactors=FALSE)
  colnames(results) <- c("Level", "Model", "NumberLoci", "TreeLength", "TreeLength.lowCI", "TreeLength.uppCI", "TreeLengthESS", "Alpha", "Alpha.lowCI", "Alpha.uppCI", "AlphaESS", "stdSplits")
  results$NumberLoci <- as.numeric(results$NumberLoci)
  results$TreeLength <- as.numeric(results$TreeLength)
  results$TreeLength.lowCI <- as.numeric(results$TreeLength.lowCI)
  results$TreeLength.uppCI <- as.numeric(results$TreeLength.uppCI)
  results$TreeLengthESS <- as.numeric(results$TreeLengthESS)
  results$Alpha <- as.numeric(results$Alpha)
  results$Alpha.lowCI <- as.numeric(results$Alpha.lowCI)
  results$Alpha.uppCI <- as.numeric(results$Alpha.uppCI)
  results$AlphaESS <- as.numeric(results$AlphaESS)
  results$stdSplits <- as.numeric(results$stdSplits)
  setwd(startingDir)
  return(results)
}


CheckInvocations <- function(workingDir){  #broken with new models
# only works for RAxML
# read in info filenames - scrape out model, dataset, and rep from name
# then grep for invocation line and scrape model and dataset to make sure it matches
  origWD <- getwd()
  setwd(workingDir)
  seeds <- NULL
  infoFiles <- system("ls *info*", intern=T)
  for(i in sequence(length(infoFiles))){
    modLine <- strsplit(infoFiles[i], "[.,_]")[[1]]
    mod1 <- modLine[3]
    dat1 <- getMissingDataAmount(infoFiles[i])
    invocLine <- strsplit(system(paste("grep -A 2 'RAxML was called as follows:'", infoFiles[i]), intern=TRUE)[3], split=" ")[[1]]
    mod2 <- invocLine[(grep("-s", invocLine)[1] +1)]
    seeds <- c(seeds, invocLine[grep("^\\d\\d\\d+$", invocLine)][invocLine[grep("^\\d\\d\\d+$", invocLine)] != "1000"])
    dat2 <- getMissingDataAmount(invocLine[5])
    if(mod1 != mod2)  
      print(paste("model invocation is wrong:", infoFiles[i]))
    if(dat1 != dat2)
      print(paste("dataset invocation is wrong:", infoFiles[i]))
  }
  setwd(origWD)
  return(as.numeric(seeds))
}

CheckSeeds <- function(seeds) {
# takes a simple string and checks for repeats
  x1 <- NULL
  sorted.seeds <- sort(seeds)
  for (i in 1: length(seeds)-1) {
    x2 <- c(abs(sorted.seeds[i])-abs(sorted.seeds[i+1]))
    x1 <- c(x1, x2)
  }
  if (0 %in% x1)
    print(as.matrix(paste("repeat",  sort(seeds)[which(x1 == 0)])))
  if (!0 %in% x1)
    print("yahoo all are good!")
} 





################################################
#################   END   ######################
################################################








