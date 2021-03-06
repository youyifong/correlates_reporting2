renv::activate(project = here::here(".."))    
    # There is a bug on Windows that prevents renv from working properly. The following code provides a workaround:
    if (.Platform$OS.type == "windows") .libPaths(c(paste0(Sys.getenv ("R_HOME"), "/library"), .libPaths()))
    
library(kyotil)
library(tools) # toTitleCase
library(xtable) # this is a dependency of kyotil


# 
ve.az=read.csv("../data_clean/AZChAd26UKphase3FengetalCorrelates.csv")

hist.shrink=c(bindSpike=2,pseudoneutid50=3)
for (a in c("bindSpike","pseudoneutid50")) {
#a="pseudoneutid50"
    myprint(a)
    ylim=c(0, 1)    
    cols=c("blue","green","orange")
    studies=c("COVE","ENSEMBLE","AZ-COV002")
    hist.col.ls=list()
    hist.col <- c(col2rgb("olivedrab3")) # orange, darkgoldenrod2
    hist.col <- rgb(hist.col[1], hist.col[2], hist.col[3], alpha=255*0.4, maxColorValue=255)
    hist.col.ls[[2]]=hist.col
    hist.col <- c(col2rgb("lightblue")) # orange, darkgoldenrod2
    hist.col <- rgb(hist.col[1], hist.col[2], hist.col[3], alpha=255*0.4, maxColorValue=255)
    hist.col.ls[[1]]=hist.col

    ## combine xlim from different trials. do janssen first because we want to source _common.R for moderna last so that we get the proper lloxs
    ## source _commom.R
    ## save markers
    xlim.ls=list()
    marker=list()
    for (i in 2:1) {        
        TRIAL=ifelse (i==1, "moderna_real", ifelse(startsWith(a,"pseudo"), "janssen_pooled_realPsV", "janssen_pooled_real"))
        Sys.setenv("TRIAL"=TRIAL)
        COR=ifelse (i==1,"D57","D29IncludeNotMolecConfirmedstart1")
        source(here::here("..", "_common.R"))
        
        # uloq censoring    
        tmp="Day"%.%config.cor$tpeak %.% a
        dat.mock[[tmp]] <- ifelse(dat.mock[[tmp]] > log10(uloqs[a]), log10(uloqs[a]), dat.mock[[tmp]])
        
        dat.vac.seroneg=subset(dat.mock, Trt==1 & ph1)
        xlim=get.range.cor(dat.vac.seroneg, a, config.cor$tpeak)
        xlim.ls[[i]]=xlim
        
        marker[[i]]=dat.vac.seroneg[["Day"%.%tpeak%.%a]]
    }
    xlim=c(min(xlim.ls[[1]][1], xlim.ls[[2]][1]), max(xlim.ls[[1]][2], xlim.ls[[2]][2]))

    myfigure()
        par(las=1, cex.axis=0.9, cex.lab=1)# axis label orientation
        
        # depends on several variables from sourcing _common.R: lloxs, labels.assays, draw.x.axis.cor
        overall.ve.ls=list()
        for (i in 1:2) {
            TRIAL=ifelse (i==1, "moderna_real", ifelse(startsWith(a,"pseudo"), "janssen_pooled_realPsV", "janssen_pooled_real"))
            COR=ifelse (i==1,"D57","D29IncludeNotMolecConfirmedstart1")
            study_name=studies[i]
    #        config <- config::get(config = Sys.getenv("TRIAL"))
    #        config.cor <- config::get(config = COR)
            
            load(here::here("output", TRIAL, COR, "marginalized.risk.no.marker."%.%study_name%.%".Rdata"))
            load(here::here("output", TRIAL, COR, "marginalized.risk."%.%study_name%.%".Rdata"))
            risks=get("risks.all.1")[[a]]        
            overall.ve.ls[[i]]=overall.ve
            
            est = 1 - risks$prob/res.plac.cont["est"]
            boot = 1 - t( t(risks$boot)/res.plac.cont[2:(1+ncol(risks$boot))] )                         
            ci.band=apply(boot, 1, function (x) quantile(x, c(.025,.975)))                
        
            mymatplot(risks$marker, t(rbind(est, ci.band)), type="l", lty=c(1,3,3), lwd=2.5, make.legend=F, col=cols[i], ylab=paste0("Controlled VE"), xlab=labels.assays.short[a]%.%" (=s)", 
                #main=paste0(labels.assays.long["Day"%.%tpeak,a]),
                ylim=ylim, xlim=xlim, yaxt="n", xaxt="n", draw.x.axis=F, add=i==2)
            draw.x.axis.cor(xlim, lloxs[a])
            yat=seq(-1,1,by=.1)
            axis(side=2,at=yat,labels=(yat*100)%.%"%")            
        
            # add histogram
    #        par(new=TRUE) #this changes ylim, so we cannot use it in this loop
            tmp=hist(marker[[i]],breaks=15,plot=F) # 15 is treated as a suggestion and the actual number of breaks is determined by pretty()
            tmp$density=tmp$density/hist.shrink[a] # so that it will fit vertically
            #tmp=hist(dat.vac.seroneg[["Day"%.%tpeak%.%a]],breaks=seq(min(dat.vac.seroneg[["Day"%.%tpeak%.%a]],na.rm=T), max(dat.vac.seroneg[["Day"%.%tpeak%.%a]],na.rm=T), len = 15),plot=F)
            plot(tmp,col=hist.col.ls[[i]],axes=F,labels=F,main="",xlab="",ylab="",border=0,freq=F,xlim=xlim, ylim=c(0,max(tmp$density*1.25)), add=T) 
        }
        
        # add az curve
        lines(log10(ve.az[[a]]), ve.az$VE/100, col=cols[3], lwd=2.5)
        lines(log10(ve.az[[a%.%"LL"]]), ve.az$VE/100, col=cols[3], lwd=2.5, lty=3)
        lines(log10(ve.az[[a%.%"UL"]]), ve.az$VE/100, col=cols[3], lwd=2.5, lty=3)
    
        # legend
        tmp.1=formatDouble(overall.ve.ls[[1]]*100,1)%.%"%"        
        tmp.2=formatDouble(overall.ve.ls[[2]]*100,1)%.%"%"        
        mylegend(x=6, col=cols, legend=c(
                paste0(studies[1], " (overall ",tmp.1[1], ")"), 
                paste0(studies[2], " (overall ",tmp.2[1], ")"),
                paste0(studies[3], " (overall 66.7%)") # based on Feng et al
            ), lty=1, lwd=2, cex=.8)
    
    mydev.off(file=paste0("output/meta_controlled_ve_curves_",a))
    
} # end assays
    
